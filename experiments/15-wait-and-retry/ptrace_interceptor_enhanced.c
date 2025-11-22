/*
 * Enhanced Ptrace Syscall Interceptor - Experiment 13
 * Includes /proc/sys/net/* redirection for kube-proxy
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/ptrace.h>
#include <sys/wait.h>
#include <sys/user.h>
#include <sys/syscall.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>

#define MAX_STRING 4096

static int verbose = 0;

// Read string from traced process memory
static char* read_string(pid_t pid, unsigned long addr) {
    char *str = malloc(MAX_STRING);
    if (!str) return NULL;

    for (size_t i = 0; i < MAX_STRING - 1; i += sizeof(long)) {
        errno = 0;
        long data = ptrace(PTRACE_PEEKDATA, pid, addr + i, NULL);
        if (errno != 0) {
            if (i == 0) {
                free(str);
                return NULL;
            }
            str[i] = '\0';
            return str;
        }

        memcpy(str + i, &data, sizeof(long));

        // Check for null terminator
        for (size_t j = 0; j < sizeof(long); j++) {
            if (((char*)&data)[j] == '\0') {
                str[i + j] = '\0';
                return str;
            }
        }
    }
    str[MAX_STRING - 1] = '\0';
    return str;
}

// Write string to traced process memory
static int write_string(pid_t pid, unsigned long addr, const char *str) {
    size_t len = strlen(str) + 1;

    for (size_t i = 0; i < len; i += sizeof(long)) {
        long data = 0;
        size_t copy_len = (len - i < sizeof(long)) ? (len - i) : sizeof(long);
        memcpy(&data, str + i, copy_len);

        if (ptrace(PTRACE_POKEDATA, pid, addr + i, data) < 0) {
            return -1;
        }
    }
    return 0;
}

static int should_redirect(const char *path) {
    if (!path) return 0;

    // Redirect all /proc/sys/* paths
    if (strstr(path, "/proc/sys/") != NULL)
        return 1;

    // Other redirections
    if (strstr(path, "/proc/diskstats") != NULL)
        return 1;
    if (strstr(path, "/sys/fs/cgroup/cpuacct/cpuacct.usage_percpu") != NULL)
        return 1;

    return 0;
}

// Get redirect target based on path
static const char* get_redirect_target(const char *path, int flags) {
    // Handle /proc/sys/* paths - redirect to /tmp/fake-procsys/*
    if (strstr(path, "/proc/sys/") != NULL) {
        static char redirect_path[MAX_STRING];
        const char *suffix = strstr(path, "/proc/sys/");
        if (suffix) {
            suffix += strlen("/proc/sys/");
            snprintf(redirect_path, MAX_STRING, "/tmp/fake-procsys/%s", suffix);
            return redirect_path;
        }
    }

    // Handle other special paths
    if (strstr(path, "/proc/diskstats"))
        return "/tmp/fake-diskstats";
    if (strstr(path, "/sys/fs/cgroup/cpuacct/cpuacct.usage_percpu"))
        return "/tmp/fake-cpuacct-usage-percpu";

    // Fallback
    int access_mode = flags & O_ACCMODE;
    return (access_mode == O_RDONLY) ? "/dev/zero" : "/dev/null";
}

static void handle_syscall(pid_t pid) {
    struct user_regs_struct regs;
    if (ptrace(PTRACE_GETREGS, pid, 0, &regs) < 0) {
        return;
    }

    if (regs.orig_rax != __NR_open && regs.orig_rax != __NR_openat) {
        return;
    }

    unsigned long path_addr;
    int flags;

    if (regs.orig_rax == __NR_open) {
        path_addr = regs.rdi;
        flags = regs.rsi;
    } else {  // __NR_openat
        path_addr = regs.rsi;
        flags = regs.rdx;
    }

    char *path = read_string(pid, path_addr);
    if (path && should_redirect(path)) {
        const char *redirect = get_redirect_target(path, flags);
        if (redirect) {
            if (verbose) {
                fprintf(stderr, "[PTRACE:%d] %s -> %s\n", pid, path, redirect);
            }

            if (write_string(pid, path_addr, redirect) == 0) {
                ptrace(PTRACE_SETREGS, pid, 0, &regs);
            }
        }
    }
    free(path);
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s [-v] <program> [args...]\n", argv[0]);
        return 1;
    }

    int arg_offset = 1;
    if (strcmp(argv[1], "-v") == 0) {
        verbose = 1;
        arg_offset = 2;
    }

    pid_t child = fork();
    if (child == 0) {
        // Child - execute target program
        ptrace(PTRACE_TRACEME, 0, NULL, NULL);
        raise(SIGSTOP);  // Stop and wait for parent to set options
        execvp(argv[arg_offset], &argv[arg_offset]);
        perror("execvp");
        exit(1);
    }

    // Parent - trace the child
    int status;
    waitpid(child, &status, 0);

    // Set ptrace options to follow forks
    long options = PTRACE_O_TRACESYSGOOD | PTRACE_O_TRACEFORK |
                   PTRACE_O_TRACEVFORK | PTRACE_O_TRACECLONE;
    ptrace(PTRACE_SETOPTIONS, child, 0, options);

    // Continue the child
    ptrace(PTRACE_SYSCALL, child, 0, 0);

    while (1) {
        pid_t pid = waitpid(-1, &status, __WALL);
        if (pid < 0) {
            if (errno == ECHILD) {
                break;  // No more children
            }
            continue;
        }

        if (WIFEXITED(status) || WIFSIGNALED(status)) {
            continue;  // Child exited
        }

        if (!WIFSTOPPED(status)) {
            ptrace(PTRACE_SYSCALL, pid, 0, 0);
            continue;
        }

        int sig = WSTOPSIG(status);

        // Handle fork/clone events
        if (sig == (SIGTRAP | 0x80)) {
            // Syscall-stop
            handle_syscall(pid);
            ptrace(PTRACE_SYSCALL, pid, 0, 0);
        } else if ((status >> 8 == (SIGTRAP | (PTRACE_EVENT_FORK << 8))) ||
                   (status >> 8 == (SIGTRAP | (PTRACE_EVENT_VFORK << 8))) ||
                   (status >> 8 == (SIGTRAP | (PTRACE_EVENT_CLONE << 8)))) {
            // Fork/vfork/clone event - new child will be auto-traced
            ptrace(PTRACE_SYSCALL, pid, 0, 0);
        } else {
            // Forward other signals
            ptrace(PTRACE_SYSCALL, pid, 0, (sig == SIGSTOP || sig == SIGTRAP) ? 0 : sig);
        }
    }

    return 0;
}
