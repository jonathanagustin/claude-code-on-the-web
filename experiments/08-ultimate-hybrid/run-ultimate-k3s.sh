#!/bin/bash
#
# Ultimate k3s Worker Node Solution
# Experiment 08: Combining ALL successful techniques
#
# This script represents the culmination of all research, integrating:
# - Fake CNI plugin (Exp 05)
# - Enhanced ptrace with statfs() (Exp 06)
# - FUSE cgroup emulation (Exp 07)
# - All previous workarounds (Exp 01-04)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PTRACE_INTERCEPTOR="${SCRIPT_DIR}/../06-enhanced-ptrace-statfs/enhanced_ptrace_interceptor"
FUSE_CGROUPFS="${SCRIPT_DIR}/../07-fuse-cgroup-emulation/fuse_cgroupfs"
FUSE_MOUNT="/tmp/fuse-cgroup"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_header() {
    echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC} $1"
    echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Root check
if [ "$EUID" -ne 0 ]; then
    log_error "Must run as root"
    exit 1
fi

# Build all components
build_all() {
    log_header "Building All Components"

    # Build ptrace interceptor
    log_step "Building enhanced ptrace interceptor..."
    if [ ! -f "$PTRACE_INTERCEPTOR" ]; then
        gcc -o "$PTRACE_INTERCEPTOR" \
            "${SCRIPT_DIR}/../06-enhanced-ptrace-statfs/enhanced_ptrace_interceptor.c"
        [ $? -eq 0 ] && log_success "Ptrace interceptor built" || log_error "Build failed"
    else
        log_info "Ptrace interceptor already exists"
    fi

    # Build FUSE cgroupfs
    log_step "Building FUSE cgroup emulator..."
    if ! pkg-config --exists fuse; then
        log_error "libfuse-dev not installed"
        log_info "Install with: apt-get install libfuse-dev"
        exit 1
    fi

    if [ ! -f "$FUSE_CGROUPFS" ]; then
        gcc -Wall "${SCRIPT_DIR}/../07-fuse-cgroup-emulation/fuse_cgroupfs.c" \
            -o "$FUSE_CGROUPFS" `pkg-config fuse --cflags --libs`
        [ $? -eq 0 ] && log_success "FUSE cgroupfs built" || log_error "Build failed"
    else
        log_info "FUSE cgroupfs already exists"
    fi
}

# Setup fake /proc/sys files (Experiment 04)
setup_fake_procsys() {
    log_step "[Exp 04] Setting up fake /proc/sys files..."

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

    log_success "Fake /proc/sys configured"
}

# Setup /dev/kmsg workaround (Experiment 01)
setup_dev_kmsg() {
    log_step "[Exp 01] Setting up /dev/kmsg workaround..."

    if [ ! -e /dev/kmsg ]; then
        touch /dev/kmsg
    fi

    if ! mountpoint -q /dev/kmsg 2>/dev/null; then
        mount --bind /dev/null /dev/kmsg 2>/dev/null || true
    fi

    log_success "/dev/kmsg configured"
}

# Setup mount propagation (Experiment 02)
setup_mount_propagation() {
    log_step "[Exp 02] Configuring mount propagation..."
    unshare --mount --propagation unchanged bash -c 'mount --make-rshared / 2>/dev/null || true'
    log_success "Mount propagation configured"
}

# Setup fake CNI plugin (Experiment 05 - BREAKTHROUGH)
setup_fake_cni() {
    log_step "[Exp 05] Setting up fake CNI plugin (BREAKTHROUGH)..."

    mkdir -p /opt/cni/bin

    if [ ! -f /opt/cni/bin/host-local ]; then
        cat > /opt/cni/bin/host-local << 'EOF'
#!/bin/bash
echo '{"cniVersion": "0.4.0", "ips": [{"version": "4", "address": "10.244.0.1/24"}]}'
exit 0
EOF
        chmod +x /opt/cni/bin/host-local
    fi

    export PATH=$PATH:/opt/cni/bin
    log_success "Fake CNI plugin configured"
}

# Mount FUSE cgroup filesystem (Experiment 07)
mount_fuse_cgroups() {
    log_step "[Exp 07] Mounting FUSE cgroup emulator..."

    mkdir -p "$FUSE_MOUNT"

    if mountpoint -q "$FUSE_MOUNT"; then
        log_info "FUSE already mounted"
        return 0
    fi

    # Mount in background
    "$FUSE_CGROUPFS" "$FUSE_MOUNT" -o allow_other -f &
    FUSE_PID=$!

    # Wait for mount
    for i in {1..10}; do
        if mountpoint -q "$FUSE_MOUNT"; then
            log_success "FUSE cgroup mounted (PID: $FUSE_PID)"

            # Verify files are accessible
            if cat "$FUSE_MOUNT/cpu/cpu.shares" > /dev/null 2>&1; then
                log_info "FUSE files verified readable"
            else
                log_warn "FUSE mounted but files not readable"
            fi
            return 0
        fi
        sleep 0.5
    done

    log_error "FUSE mount failed"
    kill $FUSE_PID 2>/dev/null || true
    return 1
}

# Cleanup function
cleanup() {
    log_warn "Cleaning up..."
    pkill -f enhanced_ptrace_interceptor || true
    pkill -f k3s || true
    pkill -f fuse_cgroupfs || true
    fusermount -u "$FUSE_MOUNT" 2>/dev/null || true
    umount /dev/kmsg 2>/dev/null || true
}

trap cleanup EXIT INT TERM

# Main execution
main() {
    log_header "Ultimate k3s Worker Node Solution - Experiment 08"
    echo ""
    log_info "Combining ALL successful techniques:"
    echo -e "  ${CYAN}✓${NC} Fake CNI plugin          (Exp 05 - Control-plane breakthrough)"
    echo -e "  ${CYAN}✓${NC} Enhanced ptrace          (Exp 06 - statfs() interception)"
    echo -e "  ${CYAN}✓${NC} FUSE cgroup emulation    (Exp 07 - Virtual cgroupfs)"
    echo -e "  ${CYAN}✓${NC} /proc/sys redirection    (Exp 04 - Ptrace basics)"
    echo -e "  ${CYAN}✓${NC} /dev/kmsg workaround     (Exp 01 - Device fixes)"
    echo -e "  ${CYAN}✓${NC} Mount propagation        (Exp 02 - Mount fixes)"
    echo ""
    log_info "Goal: Stable worker nodes for 60+ minutes"
    echo ""

    # Build components
    build_all
    echo ""

    # Setup environment (in order of dependencies)
    log_header "Configuring Environment"
    setup_dev_kmsg
    setup_mount_propagation
    setup_fake_procsys
    setup_fake_cni
    mount_fuse_cgroups
    echo ""

    # k3s configuration
    K3S_FLAGS=(
        "server"
        # NO --disable-agent! We want worker nodes!
        "--snapshotter=fuse-overlayfs"
        "--kubelet-arg=--fail-swap-on=false"
        "--kubelet-arg=--image-gc-high-threshold=100"
        "--kubelet-arg=--image-gc-low-threshold=99"
        "--kubelet-arg=--cgroups-per-qos=false"
        "--kubelet-arg=--enforce-node-allocatable="
        "--disable=coredns,servicelb,traefik,local-storage,metrics-server"
        "--write-kubeconfig-mode=644"
        "--data-dir=/tmp/k3s-ultimate"
    )

    log_header "Starting k3s with Full Emulation Stack"
    log_info "Watch for these interceptions:"
    echo -e "  ${CYAN}[INTERCEPT-OPEN]${NC}    - /proc/sys path redirection"
    echo -e "  ${CYAN}[INTERCEPT-STATFS]${NC}  - Filesystem type spoofing (9p → ext4)"
    echo ""
    log_info "Expected behavior:"
    echo -e "  ${GREEN}1.${NC} k3s starts within 30 seconds"
    echo -e "  ${GREEN}2.${NC} kubelet initializes without errors"
    echo -e "  ${GREEN}3.${NC} Node registers as Ready"
    echo -e "  ${GREEN}4.${NC} Stability continues beyond 60 seconds"
    echo -e "  ${GREEN}5.${NC} No 'unable to find data in memory cache' errors"
    echo ""
    log_info "Monitoring suggestions:"
    echo -e "  ${CYAN}Terminal 2:${NC} watch -n5 'kubectl get nodes'"
    echo -e "  ${CYAN}Terminal 3:${NC} tail -f /tmp/k3s-ultimate/server/logs/kubelet.log"
    echo ""
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Launch k3s with ptrace interceptor
    exec "$PTRACE_INTERCEPTOR" -v /usr/local/bin/k3s "${K3S_FLAGS[@]}"
}

# Parse command line
case "${1:-}" in
    build)
        log_info "Building components only..."
        build_all
        log_success "Build complete"
        ;;
    test)
        log_info "Running component tests..."
        build_all

        log_step "Testing FUSE mount..."
        mount_fuse_cgroups
        ls -la "$FUSE_MOUNT"
        cat "$FUSE_MOUNT/cpu/cpu.shares"

        log_step "Testing ptrace..."
        "$PTRACE_INTERCEPTOR" -v echo "Ptrace test"

        log_success "All component tests passed"
        cleanup
        ;;
    *)
        main
        ;;
esac
