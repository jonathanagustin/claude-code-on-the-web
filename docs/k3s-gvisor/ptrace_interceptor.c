#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/ptrace.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/user.h>
#include <sys/syscall.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>

#define SYS_OPEN 2
#define SYS_OPENAT 257
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

// Check if path should be redirected
static int should_redirect(const char *path) {
    if (!path) return 0;

    return (strstr(path, "/proc/sys/kernel/keys/") != NULL ||
            strstr(path, "/proc/sys/kernel/panic") != NULL ||
            strstr(path, "/proc/sys/vm/panic_on_oom") != NULL ||
            strstr(path, "/proc/sys/vm/overcommit_memory") != NULL ||
            strstr(path, "/proc/diskstats") != NULL ||
            strstr(path, "/sys/fs/cgroup/cpuacct/cpuacct.usage_percpu") != NULL);
}

// Get redirect target based on flags
static const char* get_redirect_target(const char *path, int flags) {
    int access_mode = flags & O_ACCMODE;

    // Special handling for files we created
    if (strstr(path, "/proc/sys/kernel/keys/root_maxkeys"))
        return "/tmp/fake-procsys/kernel/keys/root_maxkeys";
    if (strstr(path, "/proc/sys/kernel/keys/root_maxbytes"))
        return "/tmp/fake-procsys/kernel/keys/root_maxbytes";
    if (strstr(path, "/proc/sys/vm/panic_on_oom"))
        return "/tmp/fake-procsys/vm/panic_on_oom";
    if (strstr(path, "/proc/sys/kernel/panic_on_oops"))
        return "/tmp/fake-procsys/kernel/panic_on_oops";
    if (strstr(path, "/proc/sys/kernel/panic"))
        return "/tmp/fake-procsys/kernel/panic";
    if (strstr(path, "/proc/sys/vm/overcommit_memory"))
        return "/tmp/fake-procsys/vm/overcommit_memory";
    if (strstr(path, "/proc/diskstats"))
        return "/tmp/fake-diskstats";
    if (strstr(path, "/sys/fs/cgroup/cpuacct/cpuacct.usage_percpu"))
        return "/tmp/fake-cpuacct-usage-percpu";

    // Fallback to /dev/null or /dev/zero
    if (access_mode == O_RDONLY) {
        return "/dev/zero";
    } else {
        return "/dev/null";
    }
}

static void handle_syscall(pid_t pid) {
    struct user_regs_struct regs;
    if (ptrace(PTRACE_GETREGS, pid, 0, &regs) < 0) {
        return;
    }

    if (regs.orig_rax != SYS_OPEN && regs.orig_rax != SYS_OPENAT) {
        return;
    }

    unsigned long path_addr;
    int flags;

    if (regs.orig_rax == SYS_OPEN) {
        path_addr = regs.rdi;
        flags = regs.rsi;
    } else {  // SYS_OPENAT
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

