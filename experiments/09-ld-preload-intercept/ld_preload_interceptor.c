/*
 * LD_PRELOAD Filesystem Interceptor
 *
 * Intercepts filesystem operations at the libc level to:
 * 1. Redirect /sys/fs/cgroup/* paths to /tmp/fake-cgroup/*
 * 2. Spoof statfs() results to return ext4 instead of 9p
 * 3. Provide fake cgroup files for cAdvisor
 *
 * Build: gcc -shared -fPIC -Wall ld_preload_interceptor.c -o ld_preload_interceptor.so -ldl
 * Usage: LD_PRELOAD=/path/to/ld_preload_interceptor.so k3s server [args]
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/vfs.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdarg.h>

// Filesystem magic numbers
#define NINE_P_FS_MAGIC    0x01021997  // 9p filesystem
#define EXT4_SUPER_MAGIC   0xEF53       // ext4 filesystem

// Path redirection mapping
typedef struct {
    const char *original;
    const char *redirect;
} path_mapping_t;

static path_mapping_t path_mappings[] = {
    {"/sys/fs/cgroup", "/tmp/fake-cgroup"},
    {"/proc/sys", "/tmp/fake-procsys"},
    {NULL, NULL}
};

// Function pointer types for original libc functions
typedef int (*orig_open_t)(const char *pathname, int flags, ...);
typedef int (*orig_openat_t)(int dirfd, const char *pathname, int flags, ...);
typedef int (*orig_stat_t)(const char *pathname, struct stat *statbuf);
typedef int (*orig_lstat_t)(const char *pathname, struct stat *statbuf);
typedef int (*orig_statfs_t)(const char *path, struct statfs *buf);
typedef int (*orig_fstatfs_t)(int fd, struct statfs *buf);
typedef FILE* (*orig_fopen_t)(const char *pathname, const char *mode);

// Get original libc function
static void *get_libc_func(const char *name) {
    void *func = dlsym(RTLD_NEXT, name);
    if (!func) {
        fprintf(stderr, "[LD_PRELOAD] Failed to get %s: %s\n", name, dlerror());
        exit(1);
    }
    return func;
}

// Redirect path if it matches our mappings
static const char *redirect_path(const char *path) {
    if (!path) return path;

    for (int i = 0; path_mappings[i].original != NULL; i++) {
        size_t len = strlen(path_mappings[i].original);
        if (strncmp(path, path_mappings[i].original, len) == 0) {
            static __thread char redirected[4096];
            snprintf(redirected, sizeof(redirected), "%s%s",
                     path_mappings[i].redirect, path + len);
            fprintf(stderr, "[LD_PRELOAD] Redirect: %s → %s\n", path, redirected);
            return redirected;
        }
    }

    return path;
}

// Hook: open()
int open(const char *pathname, int flags, ...) {
    static orig_open_t orig_open = NULL;
    if (!orig_open) orig_open = (orig_open_t)get_libc_func("open");

    const char *redirected = redirect_path(pathname);

    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode = va_arg(args, mode_t);
        va_end(args);
        return orig_open(redirected, flags, mode);
    }

    return orig_open(redirected, flags);
}

// Hook: openat()
int openat(int dirfd, const char *pathname, int flags, ...) {
    static orig_openat_t orig_openat = NULL;
    if (!orig_openat) orig_openat = (orig_openat_t)get_libc_func("openat");

    const char *redirected = redirect_path(pathname);

    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode = va_arg(args, mode_t);
        va_end(args);
        return orig_openat(dirfd, redirected, flags, mode);
    }

    return orig_openat(dirfd, redirected, flags);
}

// Hook: stat()
int stat(const char *pathname, struct stat *statbuf) {
    static orig_stat_t orig_stat = NULL;
    if (!orig_stat) orig_stat = (orig_stat_t)get_libc_func("stat");

    const char *redirected = redirect_path(pathname);
    return orig_stat(redirected, statbuf);
}

// Hook: lstat()
int lstat(const char *pathname, struct stat *statbuf) {
    static orig_lstat_t orig_lstat = NULL;
    if (!orig_lstat) orig_lstat = (orig_lstat_t)get_libc_func("lstat");

    const char *redirected = redirect_path(pathname);
    return orig_lstat(redirected, statbuf);
}

// Hook: statfs() - SPOOF FILESYSTEM TYPE
int statfs(const char *path, struct statfs *buf) {
    static orig_statfs_t orig_statfs = NULL;
    if (!orig_statfs) orig_statfs = (orig_statfs_t)get_libc_func("statfs");

    int result = orig_statfs(path, buf);

    // If filesystem is 9p, spoof it as ext4
    if (result == 0 && buf->f_type == NINE_P_FS_MAGIC) {
        fprintf(stderr, "[LD_PRELOAD] statfs(%s): Spoofing 9p (0x%lx) as ext4 (0x%x)\n",
                path, (unsigned long)buf->f_type, EXT4_SUPER_MAGIC);
        buf->f_type = EXT4_SUPER_MAGIC;
    }

    return result;
}

// Hook: fstatfs() - SPOOF FILESYSTEM TYPE
int fstatfs(int fd, struct statfs *buf) {
    static orig_fstatfs_t orig_fstatfs = NULL;
    if (!orig_fstatfs) orig_fstatfs = (orig_fstatfs_t)get_libc_func("fstatfs");

    int result = orig_fstatfs(fd, buf);

    // If filesystem is 9p, spoof it as ext4
    if (result == 0 && buf->f_type == NINE_P_FS_MAGIC) {
        fprintf(stderr, "[LD_PRELOAD] fstatfs(fd=%d): Spoofing 9p (0x%lx) as ext4 (0x%x)\n",
                fd, (unsigned long)buf->f_type, EXT4_SUPER_MAGIC);
        buf->f_type = EXT4_SUPER_MAGIC;
    }

    return result;
}

// Hook: fopen()
FILE *fopen(const char *pathname, const char *mode) {
    static orig_fopen_t orig_fopen = NULL;
    if (!orig_fopen) orig_fopen = (orig_fopen_t)get_libc_func("fopen");

    const char *redirected = redirect_path(pathname);
    return orig_fopen(redirected, mode);
}

// Constructor - runs when library is loaded
__attribute__((constructor))
static void init_interceptor(void) {
    fprintf(stderr, "========================================\n");
    fprintf(stderr, "[LD_PRELOAD] Filesystem Interceptor Loaded\n");
    fprintf(stderr, "========================================\n");
    fprintf(stderr, "Path redirections:\n");
    for (int i = 0; path_mappings[i].original != NULL; i++) {
        fprintf(stderr, "  %s → %s\n",
                path_mappings[i].original,
                path_mappings[i].redirect);
    }
    fprintf(stderr, "Filesystem type spoofing: 9p → ext4\n");
    fprintf(stderr, "========================================\n");
}
