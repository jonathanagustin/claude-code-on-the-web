#!/bin/bash
#
# Run k3s with enhanced ptrace interceptor
#
# This script combines all workarounds from previous experiments
# with the new enhanced ptrace interceptor that spoofs statfs() results.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERCEPTOR="${SCRIPT_DIR}/enhanced_ptrace_interceptor"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

# Build interceptor if not present
if [ ! -f "$INTERCEPTOR" ]; then
    log_info "Building enhanced ptrace interceptor..."
    gcc -o "$INTERCEPTOR" "${SCRIPT_DIR}/enhanced_ptrace_interceptor.c"
    if [ $? -ne 0 ]; then
        log_error "Failed to compile interceptor"
        exit 1
    fi
    log_info "Interceptor built successfully"
fi

# Setup fake /proc/sys files
setup_fake_procsys() {
    log_info "Setting up fake /proc/sys files..."

    mkdir -p /tmp/fake-procsys/kernel/keys
    mkdir -p /tmp/fake-procsys/vm
    mkdir -p /tmp/fake-procsys/fs

    # Kernel parameters
    echo "65536" > /tmp/fake-procsys/kernel/keys/root_maxkeys
    echo "25000000" > /tmp/fake-procsys/kernel/keys/root_maxbytes
    echo "1" > /tmp/fake-procsys/kernel/panic
    echo "1" > /tmp/fake-procsys/kernel/panic_on_oops
    echo "262144" > /tmp/fake-procsys/kernel/threads-max
    echo "65536" > /tmp/fake-procsys/kernel/pid_max

    # VM parameters
    echo "1" > /tmp/fake-procsys/vm/overcommit_memory
    echo "0" > /tmp/fake-procsys/vm/panic_on_oom
    echo "100" > /tmp/fake-procsys/vm/overcommit_ratio

    # FS parameters
    echo "1048576" > /tmp/fake-procsys/fs/inotify/max_user_watches
    echo "128" > /tmp/fake-procsys/fs/inotify/max_user_instances

    log_info "Fake /proc/sys files created"
}

# Setup /dev/kmsg workaround
setup_dev_kmsg() {
    log_info "Setting up /dev/kmsg workaround..."

    if [ ! -e /dev/kmsg ]; then
        touch /dev/kmsg
    fi

    # Check if already mounted
    if ! mountpoint -q /dev/kmsg; then
        mount --bind /dev/null /dev/kmsg 2>/dev/null || true
    fi

    log_info "/dev/kmsg configured"
}

# Setup mount propagation
setup_mount_propagation() {
    log_info "Configuring mount propagation..."

    # Make root shared
    unshare --mount --propagation unchanged bash -c 'mount --make-rshared / 2>/dev/null || true'

    log_info "Mount propagation configured"
}

# Setup fake CNI plugin (from Experiment 05 breakthrough)
setup_fake_cni() {
    log_info "Setting up fake CNI plugin (Experiment 05 breakthrough)..."

    mkdir -p /opt/cni/bin

    if [ ! -f /opt/cni/bin/host-local ]; then
        cat > /opt/cni/bin/host-local << 'EOF'
#!/bin/bash
# Minimal fake CNI plugin for control-plane-only mode
# Returns valid JSON to satisfy k3s initialization checks
echo '{"cniVersion": "0.4.0", "ips": [{"version": "4", "address": "10.244.0.1/24"}]}'
exit 0
EOF
        chmod +x /opt/cni/bin/host-local
        log_info "Fake CNI plugin created"
    fi

    export PATH=$PATH:/opt/cni/bin
}

# Cleanup function
cleanup() {
    log_warn "Cleaning up..."
    pkill -f enhanced_ptrace_interceptor || true
    pkill -f k3s || true
    umount /dev/kmsg 2>/dev/null || true
}

trap cleanup EXIT INT TERM

# Main execution
main() {
    log_info "Starting k3s with enhanced ptrace interception for WORKER NODES"
    log_info "================================================================"
    log_info "Building on Experiment 05 breakthrough (fake CNI) + Experiment 04 (ptrace)"
    log_info "Goal: Enable stable worker nodes with statfs() interception"
    log_info ""

    # Setup environment
    setup_fake_procsys
    setup_dev_kmsg
    setup_mount_propagation
    setup_fake_cni  # NEW: From Experiment 05

    # k3s flags for WORKER NODE testing (NOT --disable-agent)
    K3S_FLAGS=(
        "server"
        # NO --disable-agent! We want worker nodes enabled
        "--snapshotter=fuse-overlayfs"
        "--kubelet-arg=--fail-swap-on=false"
        "--kubelet-arg=--image-gc-high-threshold=100"
        "--kubelet-arg=--image-gc-low-threshold=99"
        "--kubelet-arg=--cgroups-per-qos=false"
        "--kubelet-arg=--enforce-node-allocatable="
        "--disable=coredns,servicelb,traefik,local-storage,metrics-server"
        "--write-kubeconfig-mode=644"
    )

    log_info "Starting k3s with enhanced interceptor (verbose mode)..."
    log_info "Expected improvements over Experiment 04:"
    log_info "  - statfs() interception → cAdvisor sees ext4 instead of 9p"
    log_info "  - Stability beyond 30-60 seconds?"
    log_info "  - Worker node remains Ready?"
    log_info ""
    log_info "Watch for:"
    log_info "  [INTERCEPT-OPEN] - /proc/sys path redirection"
    log_info "  [INTERCEPT-STATFS] - filesystem type spoofing"
    log_info ""

    # Run k3s with interceptor
    exec "$INTERCEPTOR" -v /usr/local/bin/k3s "${K3S_FLAGS[@]}"
}

# Parse command line arguments
case "${1:-}" in
    build)
        log_info "Building interceptor only..."
        gcc -o "$INTERCEPTOR" "${SCRIPT_DIR}/enhanced_ptrace_interceptor.c"
        log_info "Build complete: $INTERCEPTOR"
        ;;
    test)
        log_info "Testing interceptor with test program..."
        if [ ! -f "${SCRIPT_DIR}/test_statfs" ]; then
            gcc -o "${SCRIPT_DIR}/test_statfs" "${SCRIPT_DIR}/test_statfs.c"
        fi
        log_info "Without interception:"
        "${SCRIPT_DIR}/test_statfs"
        log_info ""
        log_info "With interception:"
        "$INTERCEPTOR" -v "${SCRIPT_DIR}/test_statfs"
        ;;
    *)
        main
        ;;
esac
