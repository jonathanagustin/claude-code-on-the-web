/*
 * Test program for LD_PRELOAD interceptor
 */

#include <stdio.h>
#include <sys/vfs.h>
#include <fcntl.h>
#include <unistd.h>

int main() {
    struct statfs buf;
    int fd;
    char content[256];

    printf("Testing LD_PRELOAD interceptor...\n\n");

    // Test 1: statfs() on root (should be spoofed to ext4)
    printf("Test 1: statfs(\"/\") to check filesystem type spoofing\n");
    if (statfs("/", &buf) == 0) {
        printf("  f_type = 0x%lx", (unsigned long)buf.f_type);
        if (buf.f_type == 0xEF53) {
            printf(" (ext4 - SPOOFED ✓)\n");
        } else if (buf.f_type == 0x01021997) {
            printf(" (9p - NOT spoofed ✗)\n");
        } else {
            printf(" (other)\n");
        }
    } else {
        perror("  statfs failed");
    }

    printf("\n");

    // Test 2: open() redirection
    printf("Test 2: open(\"/sys/fs/cgroup/cpu/cpu.shares\") redirection\n");
    fd = open("/sys/fs/cgroup/cpu/cpu.shares", O_RDONLY);
    if (fd >= 0) {
        ssize_t n = read(fd, content, sizeof(content) - 1);
        if (n > 0) {
            content[n] = '\0';
            printf("  Content: %s", content);
            printf("  ✓ Read successful (redirected to /tmp/fake-cgroup)\n");
        }
        close(fd);
    } else {
        perror("  open failed");
        printf("  ✗ Redirection failed\n");
    }

    printf("\n");

    // Test 3: fopen() redirection
    printf("Test 3: fopen(\"/proc/sys/kernel/pid_max\") redirection\n");
    FILE *f = fopen("/proc/sys/kernel/pid_max", "r");
    if (f) {
        if (fgets(content, sizeof(content), f)) {
            printf("  Content: %s", content);
            printf("  ✓ Read successful (redirected to /tmp/fake-procsys)\n");
        }
        fclose(f);
    } else {
        perror("  fopen failed");
        printf("  ✗ Redirection failed\n");
    }

    printf("\nAll tests complete!\n");
    return 0;
}
