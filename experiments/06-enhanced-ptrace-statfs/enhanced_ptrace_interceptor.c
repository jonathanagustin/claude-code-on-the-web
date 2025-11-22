/*
 * Enhanced Ptrace Interceptor with statfs() Support
 *
 * This interceptor extends Experiment 04 by also intercepting statfs() syscalls
 * and modifying the returned filesystem type from 9p to ext4.
 *
 * Features:
 * - Intercepts open() and openat() to redirect /proc/sys paths
 * - Intercepts statfs() and fstatfs() to spoof filesystem type
 * - Tracks syscall entry vs exit state
 * - Handles multi-process tracing (fork/clone)
 */

#define _GNU_SOURCE
#include <sys/ptrace.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/user.h>
#include <sys/syscall.h>
#include <sys/vfs.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <signal.h>

// Filesystem magic numbers
#define NINE_P_FS_MAGIC    0x01021997  // 9p filesystem
#define EXT4_SUPER_MAGIC   0xEF53       // ext4 filesystem
#define OVERLAY_SUPER_MAGIC 0x794c7630  // overlayfs

// Syscall state tracking
typedef enum {
    SYSCALL_ENTRY,
    SYSCALL_EXIT
} syscall_state_t;

// Process state tracking
typedef struct {
    pid_t pid;
    syscall_state_t state;
    long last_syscall;
} process_state_t;

// Global state (simple single-process version, can be extended for multi-process)
static syscall_state_t current_state = SYSCALL_ENTRY;
static int verbose = 0;

// Read string from traced process memory
int read_string_from_tracee(pid_t pid, unsigned long addr, char *str, size_t maxlen) {
    size_t i = 0;
    long data;

    if (addr == 0) {
        str[0] = '\0';
        return -1;
    }

    while (i < maxlen - 1) {
        errno = 0;
        data = ptrace(PTRACE_PEEKDATA, pid, addr + i, NULL);
        if (errno != 0) {
            str[i] = '\0';
            return -1;
        }

        memcpy(str + i, &data, sizeof(long));

        // Check for null terminator
        for (size_t j = 0; j < sizeof(long) && i + j < maxlen - 1; j++) {
            if (str[i + j] == '\0') {
                return 0;
            }
        }

        i += sizeof(long);
    }

    str[maxlen - 1] = '\0';
    return 0;
}

// Write string to traced process memory
int write_string_to_tracee(pid_t pid, unsigned long addr, const char *str) {
    size_t len = strlen(str) + 1;
    size_t i;

    for (i = 0; i < len; i += sizeof(long)) {
        long data = 0;
        size_t copy_len = (len - i < sizeof(long)) ? (len - i) : sizeof(long);
        memcpy(&data, str + i, copy_len);

        if (ptrace(PTRACE_POKEDATA, pid, addr + i, data) < 0) {
            return -1;
        }
    }

    return 0;
}

// Read memory buffer from tracee
int read_memory(pid_t pid, unsigned long addr, void *buf, size_t len) {
    size_t i;
    long data;

    for (i = 0; i < len; i += sizeof(long)) {
        errno = 0;
        data = ptrace(PTRACE_PEEKDATA, pid, addr + i, NULL);
        if (errno != 0) {
            return -1;
        }

        size_t copy_len = (len - i < sizeof(long)) ? (len - i) : sizeof(long);
        memcpy((char *)buf + i, &data, copy_len);
    }

    return 0;
}

// Write memory buffer to tracee
int write_memory(pid_t pid, unsigned long addr, const void *buf, size_t len) {
    size_t i;

    for (i = 0; i < len; i += sizeof(long)) {
        long data = 0;
        size_t copy_len = (len - i < sizeof(long)) ? (len - i) : sizeof(long);
        memcpy(&data, (char *)buf + i, copy_len);

        if (ptrace(PTRACE_POKEDATA, pid, addr + i, data) < 0) {
            return -1;
        }
    }

    return 0;
}

// Handle open()/openat() syscall entry
void handle_open_entry(pid_t pid, struct user_regs_struct *regs) {
    unsigned long path_addr;
    char path[4096];

    // Get path argument (different for open vs openat)
    if (regs->orig_rax == SYS_open) {
        path_addr = regs->rdi;  // First argument
    } else if (regs->orig_rax == SYS_openat) {
        path_addr = regs->rsi;  // Second argument
    } else {
        return;
    }

    if (read_string_from_tracee(pid, path_addr, path, sizeof(path)) < 0) {
        return;
    }

    // Check if path starts with /proc/sys/
    if (strncmp(path, "/proc/sys/", 10) == 0) {
        char new_path[4096];
        snprintf(new_path, sizeof(new_path), "/tmp/fake-procsys/%s", path + 10);

        if (write_string_to_tracee(pid, path_addr, new_path) == 0) {
            if (verbose) {
                printf("[INTERCEPT-OPEN] %s -> %s\n", path, new_path);
            }
        }
    }
}

// Handle statfs()/fstatfs() syscall exit
void handle_statfs_exit(pid_t pid, struct user_regs_struct *regs) {
    struct statfs buf;
    unsigned long buffer_addr;

    // Check if syscall succeeded (return value >= 0)
    if ((long)regs->rax < 0) {
        return;  // Syscall failed, don't modify
    }

    // Get buffer argument (different for statfs vs fstatfs)
    if (regs->orig_rax == SYS_statfs) {
        buffer_addr = regs->rsi;  // Second argument
    } else if (regs->orig_rax == SYS_fstatfs) {
        buffer_addr = regs->rsi;  // Second argument
    } else {
        return;
    }

    // Read struct statfs from tracee memory
    if (read_memory(pid, buffer_addr, &buf, sizeof(buf)) < 0) {
        if (verbose) {
            fprintf(stderr, "[ERROR] Failed to read statfs buffer\n");
        }
        return;
    }

    // Check if filesystem is 9p
    if (buf.f_type == NINE_P_FS_MAGIC) {
        if (verbose) {
            printf("[INTERCEPT-STATFS] Detected 9p filesystem (0x%lx), spoofing as ext4 (0x%x)\n",
                   (unsigned long)buf.f_type, EXT4_SUPER_MAGIC);
        }

        // Change to ext4
        buf.f_type = EXT4_SUPER_MAGIC;

        // Optionally adjust other fields to look more like ext4
        // buf.f_bsize typically 4096 for ext4
        // buf.f_namelen typically 255 for ext4
        if (buf.f_namelen == 0 || buf.f_namelen > 255) {
            buf.f_namelen = 255;
        }

        // Write modified structure back
        if (write_memory(pid, buffer_addr, &buf, sizeof(buf)) < 0) {
            if (verbose) {
                fprintf(stderr, "[ERROR] Failed to write modified statfs buffer\n");
            }
        }
    }
}

// Signal handler for clean exit
static volatile int keep_running = 1;

void handle_signal(int sig) {
    keep_running = 0;
}

int main(int argc, char **argv) {
    pid_t child;
    int status;
    struct user_regs_struct regs;

    if (argc < 2) {
        fprintf(stderr, "Usage: %s [-v] <program> [args...]\n", argv[0]);
        fprintf(stderr, "  -v: Verbose output\n");
        return 1;
    }

    // Check for verbose flag
    int arg_offset = 1;
    if (strcmp(argv[1], "-v") == 0) {
        verbose = 1;
        arg_offset = 2;
        if (argc < 3) {
            fprintf(stderr, "Usage: %s [-v] <program> [args...]\n", argv[0]);
            return 1;
        }
    }

    // Setup signal handlers
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);

    printf("[INFO] Starting enhanced ptrace interceptor\n");
    printf("[INFO] Intercepting: open, openat, statfs, fstatfs\n");
    printf("[INFO] Spoofing 9p filesystem as ext4\n");

    child = fork();

    if (child == 0) {
        // Child process: allow tracing and execute target program
        if (ptrace(PTRACE_TRACEME, 0, NULL, NULL) < 0) {
            perror("ptrace(TRACEME)");
            return 1;
        }

        // Execute target program
        execvp(argv[arg_offset], &argv[arg_offset]);
        perror("execvp");
        return 1;
    }

    // Parent process: trace the child
    printf("[INFO] Tracing process %d\n", child);

    // Wait for child to stop on execve
    waitpid(child, &status, 0);

    // Set ptrace options
    if (ptrace(PTRACE_SETOPTIONS, child, 0,
               PTRACE_O_TRACESYSGOOD |      // Distinguish syscall stops
               PTRACE_O_TRACEFORK |          // Trace forks
               PTRACE_O_TRACEVFORK |         // Trace vforks
               PTRACE_O_TRACECLONE) < 0) {   // Trace clones
        perror("ptrace(SETOPTIONS)");
        return 1;
    }

    current_state = SYSCALL_ENTRY;

    // Main interception loop
    while (keep_running) {
        // Continue until next syscall
        if (ptrace(PTRACE_SYSCALL, child, 0, 0) < 0) {
            perror("ptrace(SYSCALL)");
            break;
        }

        // Wait for child to stop
        if (waitpid(child, &status, 0) < 0) {
            perror("waitpid");
            break;
        }

        // Check if child exited
        if (WIFEXITED(status)) {
            printf("[INFO] Process exited with status %d\n", WEXITSTATUS(status));
            break;
        }

        if (WIFSIGNALED(status)) {
            printf("[INFO] Process terminated by signal %d\n", WTERMSIG(status));
            break;
        }

        // Check if this is a syscall stop
        if (WIFSTOPPED(status) && WSTOPSIG(status) == (SIGTRAP | 0x80)) {
            // Get registers to see which syscall
            if (ptrace(PTRACE_GETREGS, child, 0, &regs) < 0) {
                perror("ptrace(GETREGS)");
                continue;
            }

            if (current_state == SYSCALL_ENTRY) {
                // Syscall entry: modify arguments
                if (regs.orig_rax == SYS_open || regs.orig_rax == SYS_openat) {
                    handle_open_entry(child, &regs);
                }
                current_state = SYSCALL_EXIT;
            } else {
                // Syscall exit: modify return values
                if (regs.orig_rax == SYS_statfs || regs.orig_rax == SYS_fstatfs) {
                    handle_statfs_exit(child, &regs);
                }
                current_state = SYSCALL_ENTRY;
            }
        } else if (WIFSTOPPED(status)) {
            // Some other signal, forward it to the child
            int sig = WSTOPSIG(status);
            if (ptrace(PTRACE_SYSCALL, child, 0, sig) < 0) {
                perror("ptrace(SYSCALL with signal)");
                break;
            }
        }
    }

    printf("[INFO] Interceptor exiting\n");
    return 0;
}
