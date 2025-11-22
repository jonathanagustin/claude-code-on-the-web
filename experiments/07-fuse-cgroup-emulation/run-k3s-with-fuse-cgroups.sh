#!/bin/bash
#
# Run k3s with FUSE cgroup emulation + enhanced ptrace
#
# This script combines ALL workarounds:
# 1. FUSE cgroup filesystem (Experiment 07)
# 2. Enhanced ptrace with statfs() interception (Experiment 06)
# 3. Fake CNI plugin (Experiment 05)
# 4. All previous fixes (Experiments 01-04)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUSE_CGROUPFS="${SCRIPT_DIR}/fuse_cgroupfs"
PTRACE_INTERCEPTOR="${SCRIPT_DIR}/../06-enhanced-ptrace-statfs/enhanced_ptrace_interceptor"
FUSE_MOUNT="/tmp/fuse-cgroup"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check root
if [ "$EUID" -ne 0 ]; then
    log_error "Must run as root"
    exit 1
fi

# Build FUSE cgroupfs if needed
build_fuse() {
    log_step "Building FUSE cgroup emulator..."

    # Check for FUSE development files
    if ! pkg-config --exists fuse; then
        log_error "libfuse-dev not installed. Install with: apt-get install libfuse-dev"
        exit 1
    fi

    if [ ! -f "$FUSE_CGROUPFS" ]; then
        gcc -Wall "${SCRIPT_DIR}/fuse_cgroupfs.c" -o "$FUSE_CGROUPFS" \
            `pkg-config fuse --cflags --libs`

        if [ $? -ne 0 ]; then
            log_error "Failed to compile FUSE cgroupfs"
            exit 1
        fi
        log_info "FUSE cgroupfs compiled successfully"
    else
        log_info "FUSE cgroupfs already built"
    fi
}

# Build ptrace interceptor if needed
build_ptrace() {
    log_step "Building enhanced ptrace interceptor..."

    if [ ! -f "$PTRACE_INTERCEPTOR" ]; then
        gcc -o "$PTRACE_INTERCEPTOR" \
            "${SCRIPT_DIR}/../06-enhanced-ptrace-statfs/enhanced_ptrace_interceptor.c"

        if [ $? -ne 0 ]; then
            log_error "Failed to compile ptrace interceptor"
            exit 1
        fi
        log_info "Ptrace interceptor compiled successfully"
    else
        log_info "Ptrace interceptor already built"
    fi
}

# Mount FUSE cgroup filesystem
mount_fuse_cgroups() {
    log_step "Mounting FUSE cgroup filesystem..."

    # Create mount point
    mkdir -p "$FUSE_MOUNT"

    # Check if already mounted
    if mountpoint -q "$FUSE_MOUNT"; then
        log_info "FUSE cgroup already mounted"
        return 0
    fi

    # Mount in background
    "$FUSE_CGROUPFS" "$FUSE_MOUNT" -o allow_other -f &
    FUSE_PID=$!

    # Wait for mount to be ready
    for i in {1..10}; do
        if mountpoint -q "$FUSE_MOUNT"; then
            log_info "FUSE cgroup mounted at $FUSE_MOUNT (PID: $FUSE_PID)"
            return 0
        fi
        sleep 0.5
    done

    log_error "FUSE mount failed to become ready"
    kill $FUSE_PID 2>/dev/null || true
    return 1
}

# Setup fake /proc/sys files
setup_fake_procsys() {
    log_step "Setting up fake /proc/sys files..."

    mkdir -p /tmp/fake-procsys/kernel/keys
    mkdir -p /tmp/fake-procsys/vm
    mkdir -p /tmp/fake-procsys/fs

    echo "65536" > /tmp/fake-procsys/kernel/keys/root_maxkeys
    echo "25000000" > /tmp/fake-procsys/kernel/keys/root_maxbytes
    echo "1" > /tmp/fake-procsys/kernel/panic
    echo "1" > /tmp/fake-procsys/kernel/panic_on_oops
    echo "262144" > /tmp/fake-procsys/kernel/threads-max
    echo "65536" > /tmp/fake-procsys/kernel/pid_max

    echo "1" > /tmp/fake-procsys/vm/overcommit_memory
    echo "0" > /tmp/fake-procsys/vm/panic_on_oom
    echo "100" > /tmp/fake-procsys/vm/overcommit_ratio

    echo "1048576" > /tmp/fake-procsys/fs/inotify/max_user_watches
    echo "128" > /tmp/fake-procsys/fs/inotify/max_user_instances

    log_info "Fake /proc/sys files created"
}

# Setup /dev/kmsg workaround
setup_dev_kmsg() {
    log_step "Setting up /dev/kmsg workaround..."

    if [ ! -e /dev/kmsg ]; then
        touch /dev/kmsg
    fi

    if ! mountpoint -q /dev/kmsg; then
        mount --bind /dev/null /dev/kmsg 2>/dev/null || true
    fi

    log_info "/dev/kmsg configured"
}

# Setup mount propagation
setup_mount_propagation() {
    log_step "Configuring mount propagation..."
    unshare --mount --propagation unchanged bash -c 'mount --make-rshared / 2>/dev/null || true'
    log_info "Mount propagation configured"
}

# Setup fake CNI plugin
setup_fake_cni() {
    log_step "Setting up fake CNI plugin..."

    mkdir -p /opt/cni/bin

    if [ ! -f /opt/cni/bin/host-local ]; then
        cat > /opt/cni/bin/host-local << 'EOF'
#!/bin/bash
echo '{"cniVersion": "0.4.0", "ips": [{"version": "4", "address": "10.244.0.1/24"}]}'
exit 0
EOF
        chmod +x /opt/cni/bin/host-local
        log_info "Fake CNI plugin created"
    fi

    export PATH=$PATH:/opt/cni/bin
}

# Create extended ptrace wrapper that redirects cgroups
create_cgroup_redirector() {
    log_step "Creating cgroup path redirector..."

    # We'll extend the ptrace interceptor to also redirect /sys/fs/cgroup paths
    # For now, create a wrapper script that sets environment variable
    cat > /tmp/k3s-with-fuse-cgroups.sh << EOF
#!/bin/bash
# Wrapper to run k3s with FUSE cgroup redirection
export FUSE_CGROUP_PATH="$FUSE_MOUNT"

# Note: This requires extending enhanced_ptrace_interceptor.c to also
# redirect /sys/fs/cgroup/* paths to \$FUSE_CGROUP_PATH/*
# For now, we'll test if cAdvisor picks up the FUSE mount automatically

exec /usr/local/bin/k3s "\$@"
EOF
    chmod +x /tmp/k3s-with-fuse-cgroups.sh

    log_info "Cgroup redirector created"
}

# Cleanup function
cleanup() {
    log_warn "Cleaning up..."
    pkill -f enhanced_ptrace_interceptor || true
    pkill -f k3s || true
    pkill -f fuse_cgroupfs || true
    fusermount -u "$FUSE_MOUNT" 2>/dev/null || true
    umount /dev/kmsg 2>/dev/null || true
    rm -f /tmp/k3s-with-fuse-cgroups.sh
}

trap cleanup EXIT INT TERM

# Main execution
main() {
    log_info "╔════════════════════════════════════════════════════════════════╗"
    log_info "║  k3s with FUSE cgroup Emulation + Enhanced Ptrace             ║"
    log_info "╚════════════════════════════════════════════════════════════════╝"
    log_info ""
    log_info "Experiment 07: Ultimate worker node solution"
    log_info "Combining:"
    log_info "  ✓ FUSE cgroup filesystem emulation"
    log_info "  ✓ Enhanced ptrace with statfs() interception"
    log_info "  ✓ Fake CNI plugin"
    log_info "  ✓ All previous workarounds"
    log_info ""

    # Build everything
    build_fuse
    build_ptrace

    # Setup environment
    setup_fake_procsys
    setup_dev_kmsg
    setup_mount_propagation
    setup_fake_cni

    # Mount FUSE cgroups
    mount_fuse_cgroups

    # Verify FUSE mount
    log_info "Verifying FUSE cgroup mount..."
    ls -la "$FUSE_MOUNT" || log_warn "FUSE mount verification failed"
    cat "$FUSE_MOUNT/cpu/cpu.shares" || log_warn "FUSE file read failed"

    create_cgroup_redirector

    # k3s flags
    K3S_FLAGS=(
        "server"
        # NO --disable-agent - we want worker nodes!
        "--snapshotter=fuse-overlayfs"
        "--kubelet-arg=--fail-swap-on=false"
        "--kubelet-arg=--image-gc-high-threshold=100"
        "--kubelet-arg=--image-gc-low-threshold=99"
        "--kubelet-arg=--cgroups-per-qos=false"
        "--kubelet-arg=--enforce-node-allocatable="
        "--disable=coredns,servicelb,traefik,local-storage,metrics-server"
        "--write-kubeconfig-mode=644"
    )

    log_info ""
    log_info "Starting k3s with full emulation stack..."
    log_info "Expected improvements:"
    log_info "  • cgroup files accessible via FUSE"
    log_info "  • Filesystem type spoofed as ext4"
    log_info "  • All initialization checks passing"
    log_info "  • Worker node stable >60 minutes?"
    log_info ""
    log_info "Watch for:"
    log_info "  [INTERCEPT-OPEN] - /proc/sys redirection"
    log_info "  [INTERCEPT-STATFS] - filesystem spoofing"
    log_info "  [FUSE] - cgroup file access"
    log_info ""

    # Run k3s with ptrace interceptor
    # TODO: Extend interceptor to also redirect /sys/fs/cgroup paths
    log_warn "Note: Full cgroup redirection requires ptrace extension (TODO)"
    log_info "Testing with FUSE mounted at $FUSE_MOUNT..."

    exec "$PTRACE_INTERCEPTOR" -v /tmp/k3s-with-fuse-cgroups.sh "${K3S_FLAGS[@]}"
}

# Parse arguments
case "${1:-}" in
    build)
        log_info "Building components only..."
        build_fuse
        build_ptrace
        log_info "Build complete"
        ;;
    test-fuse)
        log_info "Testing FUSE cgroup mount only..."
        build_fuse
        mount_fuse_cgroups
        log_info "FUSE mounted. Testing..."
        ls -la "$FUSE_MOUNT"
        echo ""
        log_info "Reading cgroup files:"
        cat "$FUSE_MOUNT/cpu/cpu.shares"
        cat "$FUSE_MOUNT/memory/memory.limit_in_bytes"
        cat "$FUSE_MOUNT/cpuacct/cpuacct.usage"
        echo ""
        log_info "Press Ctrl+C to unmount and exit"
        sleep infinity
        ;;
    *)
        main
        ;;
esac
