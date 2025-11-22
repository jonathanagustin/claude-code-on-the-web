/*
 * Test program to verify statfs() interception
 *
 * This simple program calls statfs() on the root filesystem
 * and prints the filesystem type. Used to validate that the
 * ptrace interceptor successfully modifies the returned value.
 *
 * Expected output without interception:
 *   Filesystem type: 0x1021997 (9p)
 *
 * Expected output with interception:
 *   Filesystem type: 0xef53 (ext4)
 */

#include <sys/vfs.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    struct statfs buf;
    const char *path = (argc > 1) ? argv[1] : "/";

    printf("Testing statfs() on: %s\n", path);

    if (statfs(path, &buf) < 0) {
        perror("statfs");
        return 1;
    }

    printf("Filesystem type: 0x%lx\n", (unsigned long)buf.f_type);

    // Decode common filesystem types
    switch (buf.f_type) {
        case 0x01021997:
            printf("Detected: 9p filesystem\n");
            break;
        case 0xEF53:
            printf("Detected: ext4 filesystem\n");
            break;
        case 0x794c7630:
            printf("Detected: overlayfs\n");
            break;
        case 0x58465342:
            printf("Detected: xfs\n");
            break;
        case 0x9123683E:
            printf("Detected: btrfs\n");
            break;
        default:
            printf("Detected: unknown filesystem (0x%lx)\n", (unsigned long)buf.f_type);
    }

    printf("Block size: %ld\n", buf.f_bsize);
    printf("Total blocks: %lu\n", (unsigned long)buf.f_blocks);
    printf("Free blocks: %lu\n", (unsigned long)buf.f_bfree);
    printf("Max filename length: %ld\n", buf.f_namelen);

    return 0;
}
