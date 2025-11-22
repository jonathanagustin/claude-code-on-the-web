/*
 * FUSE-based cgroup Filesystem Emulator
 *
 * This program creates a virtual filesystem that emulates cgroupfs,
 * allowing cAdvisor to read cgroup files even when real cgroups are
 * unavailable or restricted in sandboxed environments.
 *
 * Build: gcc -Wall fuse_cgroupfs.c -o fuse_cgroupfs `pkg-config fuse --cflags --libs`
 * Usage: ./fuse_cgroupfs /tmp/fuse-cgroup
 */

#define FUSE_USE_VERSION 26

#include <fuse.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>
#include <sys/types.h>

// cgroup filesystem magic number
#define CGROUP_SUPER_MAGIC 0x27e0eb

// Cgroup file data structure
typedef struct {
    const char *path;
    const char *data;
    int dynamic;  // 1 if data changes over time
} cgroup_file_t;

// Emulated cgroup files with static/dynamic data
static cgroup_file_t cgroup_files[] = {
    // CPU subsystem
    {"/cpu/cpu.shares", "1024\n", 0},
    {"/cpu/cpu.cfs_period_us", "100000\n", 0},
    {"/cpu/cpu.cfs_quota_us", "-1\n", 0},
    {"/cpu/cpu.stat", "nr_periods 0\nnr_throttled 0\nthrottled_time 0\n", 0},

    // CPU accounting
    {"/cpuacct/cpuacct.usage", NULL, 1},  // Dynamic: nanoseconds since boot
    {"/cpuacct/cpuacct.stat", NULL, 1},   // Dynamic: user/system time

    // Memory
    {"/memory/memory.limit_in_bytes", "9223372036854771712\n", 0},  // ~8 EiB (unlimited)
    {"/memory/memory.usage_in_bytes", NULL, 1},  // Dynamic
    {"/memory/memory.max_usage_in_bytes", NULL, 1},  // Dynamic
    {"/memory/memory.stat", NULL, 1},  // Dynamic: detailed stats

    // Block I/O
    {"/blkio/blkio.throttle.io_service_bytes", "", 0},
    {"/blkio/blkio.throttle.io_serviced", "", 0},

    // Devices
    {"/devices/devices.list", "a *:* rwm\n", 0},  // Allow all devices

    // Freezer
    {"/freezer/freezer.state", "THAWED\n", 0},

    // Network
    {"/net_cls/net_cls.classid", "0\n", 0},
    {"/net_prio/net_prio.ifpriomap", "", 0},

    // PID
    {"/pids/pids.max", "max\n", 0},
    {"/pids/pids.current", "1\n", 0},

    {NULL, NULL, 0}  // Sentinel
};

// Subsystem directories
static const char *subsystems[] = {
    "cpu", "cpuacct", "memory", "blkio", "devices",
    "freezer", "net_cls", "net_prio", "pids", "hugetlb",
    NULL
};

// Get current time in nanoseconds (for dynamic values)
static long long get_time_ns() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

// Generate dynamic data for cgroup files
static int get_dynamic_data(const char *path, char *buf, size_t size) {
    if (strcmp(path, "/cpuacct/cpuacct.usage") == 0) {
        // Return current time as CPU usage
        snprintf(buf, size, "%lld\n", get_time_ns());
        return 0;
    }

    if (strcmp(path, "/cpuacct/cpuacct.stat") == 0) {
        // Return plausible user/system time
        long long ns = get_time_ns();
        long long user = ns / 2;   // Half user time
        long long system = ns / 4; // Quarter system time
        snprintf(buf, size, "user %lld\nsystem %lld\n", user / 10000000, system / 10000000);
        return 0;
    }

    if (strcmp(path, "/memory/memory.usage_in_bytes") == 0) {
        // Return modest memory usage (200 MB)
        snprintf(buf, size, "209715200\n");
        return 0;
    }

    if (strcmp(path, "/memory/memory.max_usage_in_bytes") == 0) {
        // Return slightly higher max usage (250 MB)
        snprintf(buf, size, "262144000\n");
        return 0;
    }

    if (strcmp(path, "/memory/memory.stat") == 0) {
        // Return detailed memory statistics
        snprintf(buf, size,
            "cache 0\n"
            "rss 209715200\n"
            "rss_huge 0\n"
            "mapped_file 0\n"
            "swap 0\n"
            "pgpgin 0\n"
            "pgpgout 0\n"
            "pgfault 0\n"
            "pgmajfault 0\n"
            "inactive_anon 0\n"
            "active_anon 209715200\n"
            "inactive_file 0\n"
            "active_file 0\n"
            "unevictable 0\n");
        return 0;
    }

    return -1;
}

// Check if path is a subsystem directory
static int is_subsystem(const char *name) {
    for (int i = 0; subsystems[i] != NULL; i++) {
        if (strcmp(name, subsystems[i]) == 0)
            return 1;
    }
    return 0;
}

// Find cgroup file entry
static cgroup_file_t *find_cgroup_file(const char *path) {
    for (int i = 0; cgroup_files[i].path != NULL; i++) {
        if (strcmp(path, cgroup_files[i].path) == 0)
            return &cgroup_files[i];
    }
    return NULL;
}

// FUSE: Get file attributes
static int cgroupfs_getattr(const char *path, struct stat *stbuf) {
    memset(stbuf, 0, sizeof(struct stat));

    // Root directory
    if (strcmp(path, "/") == 0) {
        stbuf->st_mode = S_IFDIR | 0755;
        stbuf->st_nlink = 2 + (sizeof(subsystems) / sizeof(char*)) - 1;
        return 0;
    }

    // Subsystem directories
    if (path[0] == '/' && path[1] != '\0') {
        char subsys[256];
        const char *slash = strchr(path + 1, '/');
        if (slash) {
            strncpy(subsys, path + 1, slash - path - 1);
            subsys[slash - path - 1] = '\0';
        } else {
            strcpy(subsys, path + 1);
        }

        if (is_subsystem(subsys)) {
            if (!slash) {
                // Subsystem directory itself
                stbuf->st_mode = S_IFDIR | 0755;
                stbuf->st_nlink = 2;
                return 0;
            } else {
                // File within subsystem
                cgroup_file_t *file = find_cgroup_file(path);
                if (file) {
                    stbuf->st_mode = S_IFREG | 0644;
                    stbuf->st_nlink = 1;

                    // Estimate size
                    if (file->dynamic) {
                        stbuf->st_size = 256;  // Reasonable estimate
                    } else {
                        stbuf->st_size = file->data ? strlen(file->data) : 0;
                    }
                    return 0;
                }
            }
        }
    }

    return -ENOENT;
}

// FUSE: Read directory
static int cgroupfs_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                           off_t offset, struct fuse_file_info *fi) {
    (void) offset;
    (void) fi;

    filler(buf, ".", NULL, 0);
    filler(buf, "..", NULL, 0);

    // Root directory: list subsystems
    if (strcmp(path, "/") == 0) {
        for (int i = 0; subsystems[i] != NULL; i++) {
            filler(buf, subsystems[i], NULL, 0);
        }
        return 0;
    }

    // Subsystem directory: list files
    if (path[0] == '/' && path[1] != '\0') {
        char subsys[256];
        const char *slash = strchr(path + 1, '/');
        if (slash) {
            return 0;  // No subdirectories within subsystems for now
        }

        strcpy(subsys, path + 1);
        if (is_subsystem(subsys)) {
            // List files for this subsystem
            char prefix[512];
            snprintf(prefix, sizeof(prefix), "/%s/", subsys);
            size_t prefix_len = strlen(prefix);

            for (int i = 0; cgroup_files[i].path != NULL; i++) {
                if (strncmp(cgroup_files[i].path, prefix, prefix_len) == 0) {
                    const char *filename = cgroup_files[i].path + prefix_len;
                    // Only add if it's a direct child (no further slashes)
                    if (strchr(filename, '/') == NULL) {
                        filler(buf, filename, NULL, 0);
                    }
                }
            }
            return 0;
        }
    }

    return -ENOENT;
}

// FUSE: Open file
static int cgroupfs_open(const char *path, struct fuse_file_info *fi) {
    cgroup_file_t *file = find_cgroup_file(path);
    if (file == NULL)
        return -ENOENT;

    // Only allow reading
    if ((fi->flags & O_ACCMODE) != O_RDONLY)
        return -EACCES;

    return 0;
}

// FUSE: Read file
static int cgroupfs_read(const char *path, char *buf, size_t size, off_t offset,
                        struct fuse_file_info *fi) {
    (void) fi;

    cgroup_file_t *file = find_cgroup_file(path);
    if (file == NULL)
        return -ENOENT;

    char data[1024];
    const char *content;
    size_t len;

    if (file->dynamic) {
        // Generate dynamic data
        if (get_dynamic_data(path, data, sizeof(data)) < 0)
            return -EIO;
        content = data;
    } else {
        // Use static data
        content = file->data ? file->data : "";
    }

    len = strlen(content);

    if (offset < len) {
        if (offset + size > len)
            size = len - offset;
        memcpy(buf, content + offset, size);
    } else {
        size = 0;
    }

    return size;
}

// FUSE: Get filesystem statistics
static int cgroupfs_statfs(const char *path, struct statvfs *stbuf) {
    (void) path;

    memset(stbuf, 0, sizeof(struct statvfs));

    // Return cgroup filesystem magic number
    stbuf->f_bsize = 4096;
    stbuf->f_frsize = 4096;
    stbuf->f_blocks = 0;
    stbuf->f_bfree = 0;
    stbuf->f_bavail = 0;
    stbuf->f_files = 1000;
    stbuf->f_ffree = 1000;
    stbuf->f_namemax = 255;

    return 0;
}

static struct fuse_operations cgroupfs_ops = {
    .getattr  = cgroupfs_getattr,
    .readdir  = cgroupfs_readdir,
    .open     = cgroupfs_open,
    .read     = cgroupfs_read,
    .statfs   = cgroupfs_statfs,
};

int main(int argc, char *argv[]) {
    printf("FUSE cgroup Filesystem Emulator\n");
    printf("================================\n");
    printf("Emulating cgroup v1 filesystem for cAdvisor compatibility\n");
    printf("\n");
    printf("Subsystems:\n");
    for (int i = 0; subsystems[i] != NULL; i++) {
        printf("  - %s\n", subsystems[i]);
    }
    printf("\n");

    return fuse_main(argc, argv, &cgroupfs_ops, NULL);
}
