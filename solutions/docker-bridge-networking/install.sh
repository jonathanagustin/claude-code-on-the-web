#!/bin/bash

# Install Docker Bridge Networking Solution
# Compiles and installs LD_PRELOAD interceptor and utilities

set -e

INSTALL_DIR="/usr/local/lib/docker-bridge-solution"
BIN_DIR="/usr/local/bin"

echo "================================================"
echo "Docker Bridge Networking Solution - Install"
echo "================================================"
echo

# Create installation directory
echo "Creating installation directory..."
mkdir -p "$INSTALL_DIR"

# Copy and compile the netlink interceptor
echo "Compiling netlink interceptor..."
cat > "$INSTALL_DIR/netlink_intercept.c" << 'EOF'
// LD_PRELOAD library for Docker bridge networking in gVisor
// Intercepts netlink socket operations

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

static void init() __attribute__((constructor));
static void init() {
    real_socket = dlsym(RTLD_NEXT, "socket");
    real_bind = dlsym(RTLD_NEXT, "bind");
    real_setsockopt = dlsym(RTLD_NEXT, "setsockopt");
}

// Track netlink sockets
static int is_netlink_fd[1024] = {0};

int socket(int domain, int type, int protocol) {
    int fd = real_socket(domain, type, protocol);
    if (fd >= 0 && domain == AF_NETLINK && fd < 1024) {
        is_netlink_fd[fd] = 1;
    }
    return fd;
}

int bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    if (sockfd < 1024 && is_netlink_fd[sockfd] && addr && addr->sa_family == AF_NETLINK) {
        struct sockaddr_nl *nl_addr = (struct sockaddr_nl *)addr;
        if (nl_addr->nl_groups != 0) {
            // Clear multicast groups and fake success
            struct sockaddr_nl safe_addr = *nl_addr;
            safe_addr.nl_groups = 0;
            real_bind(sockfd, (struct sockaddr*)&safe_addr, addrlen);
            return 0;
        }
    }
    return real_bind(sockfd, addr, addrlen);
}

int setsockopt(int sockfd, int level, int optname, const void *optval, socklen_t optlen) {
    if (sockfd < 1024 && is_netlink_fd[sockfd]) {
        return 0; // Fake success for netlink socket options
    }
    return real_setsockopt(sockfd, level, optname, optval, optlen);
}

int close(int fd) {
    static int (*real_close)(int) = NULL;
    if (!real_close) real_close = dlsym(RTLD_NEXT, "close");
    if (fd >= 0 && fd < 1024 && is_netlink_fd[fd]) {
        is_netlink_fd[fd] = 0;
    }
    return real_close(fd);
}
EOF

gcc -shared -fPIC -o "$INSTALL_DIR/netlink_intercept.so" "$INSTALL_DIR/netlink_intercept.c" -ldl

if [ ! -f "$INSTALL_DIR/netlink_intercept.so" ]; then
    echo "❌ Failed to compile netlink interceptor"
    exit 1
fi

echo "✅ Netlink interceptor compiled"

# Create cleanup script
echo "Creating cleanup script..."
cat > "$INSTALL_DIR/clean-docker-network.sh" << 'EOF'
#!/bin/bash
# Clean Docker network state

pkill dockerd 2>/dev/null || true
sleep 2

# Remove network namespaces
if [ -d /var/run/netns ]; then
    for ns in $(ip netns list 2>/dev/null | awk '{print $1}'); do
        ip netns del "$ns" 2>/dev/null || true
    done
fi

# Remove Docker interfaces
for iface in $(ip link show | grep -E 'docker|br-|veth' | awk '{print $2}' | sed 's/:$//' | sed 's/@.*$//'); do
    ip link del "$iface" 2>/dev/null || true
done

# Remove Docker network state
rm -rf /var/lib/docker/network/* 2>/dev/null || true
rm -f /var/lib/docker/network.db 2>/dev/null || true
EOF

chmod +x "$INSTALL_DIR/clean-docker-network.sh"

# Create Docker wrapper script
echo "Creating Docker wrapper script..."
cat > "$BIN_DIR/docker-bridge" << EOF
#!/bin/bash

# Docker with Bridge Networking Support
# Starts Docker daemon with netlink interceptor for improved networking

INTERCEPT_LIB="$INSTALL_DIR/netlink_intercept.so"
CLEANUP_SCRIPT="$INSTALL_DIR/clean-docker-network.sh"

# Check if running as root
if [ "\$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

# Function to show usage
usage() {
    echo "Usage: docker-bridge [start|stop|restart|status|clean]"
    echo
    echo "Commands:"
    echo "  start   - Start Docker daemon with bridge networking support"
    echo "  stop    - Stop Docker daemon"
    echo "  restart - Restart Docker daemon with clean state"
    echo "  status  - Check if Docker is running"
    echo "  clean   - Clean Docker network state without starting"
    echo
    echo "Notes:"
    echo "  - Uses LD_PRELOAD netlink interceptor for better networking"
    echo "  - Automatically cleans network state on restart"
    echo "  - Use '--network host' for best compatibility"
    echo "  - Bridge networking partially supported (experimental)"
}

# Function to clean network state
clean_network() {
    echo "Cleaning Docker network state..."
    bash "\$CLEANUP_SCRIPT"
    echo "✅ Network state cleaned"
}

# Function to start Docker
start_docker() {
    if pgrep dockerd > /dev/null; then
        echo "Docker is already running"
        return 0
    fi

    echo "Starting Docker daemon with bridge networking support..."
    LD_PRELOAD="\$INTERCEPT_LIB" dockerd --iptables=false > /var/log/dockerd-bridge.log 2>&1 &

    echo "Waiting for Docker to start..."
    for i in {1..15}; do
        if docker info > /dev/null 2>&1; then
            echo "✅ Docker started successfully"
            echo
            echo "Notes:"
            echo "  - Bridge networking has experimental support"
            echo "  - Use '--network host' for best results"
            echo "  - Logs: /var/log/dockerd-bridge.log"
            return 0
        fi
        sleep 1
    done

    echo "❌ Docker failed to start"
    echo "Check logs: tail /var/log/dockerd-bridge.log"
    return 1
}

# Function to stop Docker
stop_docker() {
    echo "Stopping Docker daemon..."
    pkill dockerd
    sleep 2
    echo "✅ Docker stopped"
}

# Main command handling
case "\${1:-}" in
    start)
        start_docker
        ;;
    stop)
        stop_docker
        ;;
    restart)
        stop_docker
        clean_network
        start_docker
        ;;
    status)
        if pgrep dockerd > /dev/null; then
            echo "✅ Docker is running"
            docker info 2>&1 | grep -E "Server Version|Storage Driver"
        else
            echo "❌ Docker is not running"
        fi
        ;;
    clean)
        clean_network
        ;;
    --help|-h|help)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
EOF

chmod +x "$BIN_DIR/docker-bridge"

echo "✅ Docker wrapper script created"
echo

# Installation summary
echo "================================================"
echo "Installation Complete!"
echo "================================================"
echo
echo "Installed Files:"
echo "  - $INSTALL_DIR/netlink_intercept.so"
echo "  - $INSTALL_DIR/clean-docker-network.sh"
echo "  - $BIN_DIR/docker-bridge"
echo
echo "Usage:"
echo "  docker-bridge start    # Start Docker with bridge support"
echo "  docker-bridge restart  # Restart with clean state"
echo "  docker-bridge status   # Check if running"
echo "  docker-bridge stop     # Stop Docker"
echo
echo "Recommended:"
echo "  # Start Docker"
echo "  docker-bridge start"
echo
echo "  # Use host networking for best compatibility"
echo "  docker run --network host myimage"
echo
echo "  # Bridge networking experimental"
echo "  docker run --network bridge myimage"
echo
echo "Notes:"
echo "  - Host networking is fully supported and recommended"
echo "  - Bridge networking partially works (container startup may fail)"
echo "  - See experiments/20-bridge-networking-breakthrough/ for details"
