// Enhanced LD_PRELOAD library to intercept ALL netlink socket operations

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <sys/socket.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>

// Original functions
static int (*real_socket)(int, int, int) = NULL;
static int (*real_bind)(int, const struct sockaddr *, socklen_t) = NULL;
static int (*real_setsockopt)(int, int, int, const void *, socklen_t) = NULL;
static ssize_t (*real_sendto)(int, const void *, size_t, int, const struct sockaddr *, socklen_t) = NULL;
static ssize_t (*real_recv)(int, void *, size_t, int) = NULL;
static ssize_t (*real_recvfrom)(int, void *, size_t, int, struct sockaddr *, socklen_t *) = NULL;

static void init() __attribute__((constructor));
static void init() {
    real_socket = dlsym(RTLD_NEXT, "socket");
    real_bind = dlsym(RTLD_NEXT, "bind");
    real_setsockopt = dlsym(RTLD_NEXT, "setsockopt");
    real_sendto = dlsym(RTLD_NEXT, "sendto");
    real_recv = dlsym(RTLD_NEXT, "recv");
    real_recvfrom = dlsym(RTLD_NEXT, "recvfrom");
    fprintf(stderr, "[netlink_v2] Netlink interceptor loaded\n");
}

// Track netlink sockets
static int is_netlink_fd[1024] = {0};

// Intercept socket() to track netlink sockets
int socket(int domain, int type, int protocol) {
    int fd = real_socket(domain, type, protocol);

    if (fd >= 0 && domain == AF_NETLINK) {
        if (fd < 1024) {
            is_netlink_fd[fd] = 1;
            fprintf(stderr, "[netlink_v2] Created netlink socket fd=%d\n", fd);
        }
    }

    return fd;
}

// Intercept bind() for netlink sockets
int bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    if (sockfd < 1024 && is_netlink_fd[sockfd] && addr && addr->sa_family == AF_NETLINK) {
        struct sockaddr_nl *nl_addr = (struct sockaddr_nl *)addr;

        fprintf(stderr, "[netlink_v2] bind() on netlink fd=%d, groups=0x%x\n", sockfd, nl_addr->nl_groups);

        // If trying to subscribe to RTMGRP_LINK or any multicast group, fake success
        if (nl_addr->nl_groups != 0) {
            fprintf(stderr, "[netlink_v2] Intercepting multicast group subscription - returning success\n");

            // Clear groups and do a minimal bind
            struct sockaddr_nl safe_addr = *nl_addr;
            safe_addr.nl_groups = 0;

            real_bind(sockfd, (struct sockaddr*)&safe_addr, addrlen);

            // Return success regardless
            return 0;
        }
    }

    return real_bind(sockfd, addr, addrlen);
}

// Intercept setsockopt for netlink
int setsockopt(int sockfd, int level, int optname, const void *optval, socklen_t optlen) {
    if (sockfd < 1024 && is_netlink_fd[sockfd]) {
        fprintf(stderr, "[netlink_v2] setsockopt() on netlink fd=%d, level=%d, optname=%d - faking success\n",
                sockfd, level, optname);
        return 0; // Fake success for all netlink socket options
    }

    return real_setsockopt(sockfd, level, optname, optval, optlen);
}

// Intercept sendto for netlink (netlink requests)
ssize_t sendto(int sockfd, const void *buf, size_t len, int flags,
               const struct sockaddr *dest_addr, socklen_t addrlen) {
    if (sockfd < 1024 && is_netlink_fd[sockfd]) {
        fprintf(stderr, "[netlink_v2] sendto() on netlink fd=%d, len=%zu\n", sockfd, len);
        // Let it through - actual netlink messages are OK
    }

    return real_sendto(sockfd, buf, len, flags, dest_addr, addrlen);
}

// Intercept recvfrom for netlink (responses)
ssize_t recvfrom(int sockfd, void *buf, size_t len, int flags,
                 struct sockaddr *src_addr, socklen_t *addrlen) {
    if (sockfd < 1024 && is_netlink_fd[sockfd]) {
        ssize_t result = real_recvfrom(sockfd, buf, len, flags, src_addr, addrlen);
        fprintf(stderr, "[netlink_v2] recvfrom() on netlink fd=%d, result=%zd\n", sockfd, result);
        return result;
    }

    return real_recvfrom(sockfd, buf, len, flags, src_addr, addrlen);
}

// Intercept close to cleanup tracking
int close(int fd) {
    static int (*real_close)(int) = NULL;
    if (!real_close) real_close = dlsym(RTLD_NEXT, "close");

    if (fd >= 0 && fd < 1024 && is_netlink_fd[fd]) {
        fprintf(stderr, "[netlink_v2] Closing netlink socket fd=%d\n", fd);
        is_netlink_fd[fd] = 0;
    }

    return real_close(fd);
}
