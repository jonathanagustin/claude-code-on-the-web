// Ultimate LD_PRELOAD library for Docker bridge networking in gVisor
// Intercepts netlink AND ioctl operations to fake bridge interface support

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <dlfcn.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <linux/if.h>
#include <linux/sockios.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>

// Original functions
static int (*real_socket)(int, int, int) = NULL;
static int (*real_bind)(int, const struct sockaddr *, socklen_t) = NULL;
static int (*real_setsockopt)(int, int, int, const void *, socklen_t) = NULL;
static int (*real_ioctl)(int, unsigned long, ...) = NULL;
static ssize_t (*real_sendto)(int, const void *, size_t, int, const struct sockaddr *, socklen_t) = NULL;
static ssize_t (*real_recvfrom)(int, void *, size_t, int, struct sockaddr *, socklen_t *) = NULL;

static void init() __attribute__((constructor));
static void init() {
    real_socket = dlsym(RTLD_NEXT, "socket");
    real_bind = dlsym(RTLD_NEXT, "bind");
    real_setsockopt = dlsym(RTLD_NEXT, "setsockopt");
    real_ioctl = dlsym(RTLD_NEXT, "ioctl");
    real_sendto = dlsym(RTLD_NEXT, "sendto");
    real_recvfrom = dlsym(RTLD_NEXT, "recvfrom");

    fprintf(stderr, "[netlink_v3] Ultimate netlink+ioctl interceptor loaded\n");
}

// Track netlink sockets
static int is_netlink_fd[1024] = {0};

// Intercept socket() to track netlink sockets
int socket(int domain, int type, int protocol) {
    int fd = real_socket(domain, type, protocol);

    if (fd >= 0 && domain == AF_NETLINK) {
        if (fd < 1024) {
            is_netlink_fd[fd] = 1;
            fprintf(stderr, "[netlink_v3] Created netlink socket fd=%d\n", fd);
        }
    }

    return fd;
}

// Intercept bind() for netlink sockets
int bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    if (sockfd < 1024 && is_netlink_fd[sockfd] && addr && addr->sa_family == AF_NETLINK) {
        struct sockaddr_nl *nl_addr = (struct sockaddr_nl *)addr;

        fprintf(stderr, "[netlink_v3] bind() on netlink fd=%d, groups=0x%x\n", sockfd, nl_addr->nl_groups);

        // If trying to subscribe to any multicast group, fake success
        if (nl_addr->nl_groups != 0) {
            fprintf(stderr, "[netlink_v3] Intercepting multicast subscription - faking success\n");

            // Clear groups and do minimal bind
            struct sockaddr_nl safe_addr = *nl_addr;
            safe_addr.nl_groups = 0;

            real_bind(sockfd, (struct sockaddr*)&safe_addr, addrlen);

            // Always return success
            return 0;
        }
    }

    return real_bind(sockfd, addr, addrlen);
}

// Intercept setsockopt for netlink
int setsockopt(int sockfd, int level, int optname, const void *optval, socklen_t optlen) {
    if (sockfd < 1024 && is_netlink_fd[sockfd]) {
        fprintf(stderr, "[netlink_v3] setsockopt() on netlink fd=%d, level=%d, optname=%d - faking success\n",
                sockfd, level, optname);
        return 0; // Fake success
    }

    return real_setsockopt(sockfd, level, optname, optval, optlen);
}

// Intercept ioctl - THIS IS THE KEY FOR BRIDGE DETECTION
int ioctl(int fd, unsigned long request, ...) {
    va_list args;
    void *argp;

    va_start(args, request);
    argp = va_arg(args, void *);
    va_end(args);

    // Check if this is a bridge-related ioctl
    if (request == SIOCBRADDBR || request == SIOCBRDELBR ||
        request == SIOCBRADDIF || request == SIOCBRDELIF) {

        fprintf(stderr, "[netlink_v3] Intercepted bridge ioctl request=0x%lx\n", request);

        // Let bridge operations through - they should work
        return real_ioctl(fd, request, argp);
    }

    // Check if this is checking if an interface is a bridge (SIOCGIFBR / SIOCDEVPRIVATE)
    if (request == SIOCDEVPRIVATE || request == SIOCGIFFLAGS) {
        struct ifreq *ifr = (struct ifreq *)argp;

        if (ifr && (strstr(ifr->ifr_name, "docker") || strstr(ifr->ifr_name, "br-"))) {
            fprintf(stderr, "[netlink_v3] Intercepted interface check for %s - forcing bridge type\n", ifr->ifr_name);

            // Try the real ioctl
            int result = real_ioctl(fd, request, argp);

            // If it failed, fake success
            if (result < 0) {
                fprintf(stderr, "[netlink_v3] Real ioctl failed, faking success\n");
                return 0;
            }

            return result;
        }
    }

    // Default: pass through
    return real_ioctl(fd, request, argp);
}

// Intercept sendto for netlink
ssize_t sendto(int sockfd, const void *buf, size_t len, int flags,
               const struct sockaddr *dest_addr, socklen_t addrlen) {
    if (sockfd < 1024 && is_netlink_fd[sockfd]) {
        fprintf(stderr, "[netlink_v3] sendto() on netlink fd=%d, len=%zu\n", sockfd, len);
    }

    return real_sendto(sockfd, buf, len, flags, dest_addr, addrlen);
}

// Intercept recvfrom for netlink
ssize_t recvfrom(int sockfd, void *buf, size_t len, int flags,
                 struct sockaddr *src_addr, socklen_t *addrlen) {
    if (sockfd < 1024 && is_netlink_fd[sockfd]) {
        ssize_t result = real_recvfrom(sockfd, buf, len, flags, src_addr, addrlen);
        fprintf(stderr, "[netlink_v3] recvfrom() on netlink fd=%d, result=%zd\n", sockfd, result);
        return result;
    }

    return real_recvfrom(sockfd, buf, len, flags, src_addr, addrlen);
}

// Intercept close to cleanup tracking
int close(int fd) {
    static int (*real_close)(int) = NULL;
    if (!real_close) real_close = dlsym(RTLD_NEXT, "close");

    if (fd >= 0 && fd < 1024 && is_netlink_fd[fd]) {
        fprintf(stderr, "[netlink_v3] Closing netlink socket fd=%d\n", fd);
        is_netlink_fd[fd] = 0;
    }

    return real_close(fd);
}
