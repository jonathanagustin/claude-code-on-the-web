#!/bin/bash
#
# K3s Worker Setup for gVisor Sandbox
# Automates the complete setup of k3s with worker functionality in gVisor
#
# Usage: ./setup-k3s-worker.sh [build|run|stop|status|clean]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERCEPTOR_SRC="${SCRIPT_DIR}/ptrace_interceptor.c"
INTERCEPTOR_BIN="${SCRIPT_DIR}/ptrace_interceptor"
FAKE_PROCSYS_DIR="/tmp/fake-procsys"
K3S_DATA_DIR="/tmp/k3s-data-gvisor"
K3S_LOG_DIR="/tmp/k3s-logs"
PIDFILE="/tmp/k3s-gvisor.pid"

# Color output
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

# Check if running in gVisor sandbox
check_gvisor() {
    if [ -z "$IS_SANDBOX" ]; then
        log_warn "IS_SANDBOX not set - may not be in gVisor environment"
        return 1
    fi
    log_info "Confirmed gVisor sandbox environment"
    return 0
}

# Build the ptrace interceptor
build_interceptor() {
    log_info "Building ptrace interceptor..."

    if [ ! -f "$INTERCEPTOR_SRC" ]; then
        log_error "Source file not found: $INTERCEPTOR_SRC"
        exit 1
    fi

    gcc -o "$INTERCEPTOR_BIN" "$INTERCEPTOR_SRC" -O2

    if [ $? -eq 0 ]; then
        log_info "Ptrace interceptor built successfully: $INTERCEPTOR_BIN"
    else
        log_error "Failed to build ptrace interceptor"
        exit 1
    fi
}

# Create fake /proc/sys files
setup_fake_procsys() {
    log_info "Setting up fake /proc/sys filesystem..."

    mkdir -p "$FAKE_PROCSYS_DIR/kernel/keys"
    mkdir -p "$FAKE_PROCSYS_DIR/kernel"
    mkdir -p "$FAKE_PROCSYS_DIR/vm"

    # Create kernel parameter files with realistic defaults
    echo "1000000" > "$FAKE_PROCSYS_DIR/kernel/keys/root_maxkeys"
    echo "25000000" > "$FAKE_PROCSYS_DIR/kernel/keys/root_maxbytes"
    echo "0" > "$FAKE_PROCSYS_DIR/vm/panic_on_oom"
    echo "0" > "$FAKE_PROCSYS_DIR/kernel/panic"
    echo "0" > "$FAKE_PROCSYS_DIR/kernel/panic_on_oops"
    echo "0" > "$FAKE_PROCSYS_DIR/vm/overcommit_memory"

    log_info "Fake /proc/sys files created in $FAKE_PROCSYS_DIR"

    # Create fake /proc/diskstats for cAdvisor
    cat > /tmp/fake-diskstats << 'EOF'
   8       0 sda 0 0 0 0 0 0 0 0 0 0 0
   8       1 sda1 0 0 0 0 0 0 0 0 0 0 0
 253       0 dm-0 0 0 0 0 0 0 0 0 0 0 0
EOF

    # Create fake cgroup cpuacct file
    echo "0" > /tmp/fake-cpuacct-usage-percpu

    log_info "Fake cAdvisor files created"

    # Create /dev/kmsg if missing
    if [ ! -e /dev/kmsg ]; then
        log_info "Creating /dev/kmsg symlink..."
        ln -sf /dev/null /dev/kmsg 2>/dev/null || log_warn "Could not create /dev/kmsg symlink"
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check for k3s
    if ! command -v k3s &> /dev/null; then
        log_error "k3s not found in PATH"
        exit 1
    fi

    # Check for fuse-overlayfs
    if ! command -v fuse-overlayfs &> /dev/null; then
        log_error "fuse-overlayfs not found - required for gVisor"
        exit 1
    fi

    # Check for CNI plugins
    if [ ! -d /usr/lib/cni ]; then
        log_error "CNI plugins not found in /usr/lib/cni"
        exit 1
    fi

    # Verify CAP_SYS_PTRACE capability
    if command -v capsh &> /dev/null; then
        if ! capsh --print | grep -q "cap_sys_ptrace"; then
            log_warn "CAP_SYS_PTRACE may not be available"
        else
            log_info "CAP_SYS_PTRACE capability confirmed"
        fi
    fi

    log_info "All prerequisites satisfied"
}

# Start k3s with worker
start_k3s() {
    log_info "Starting k3s with worker functionality..."

    # Ensure interceptor is built
    if [ ! -f "$INTERCEPTOR_BIN" ]; then
        build_interceptor
    fi

    # Setup fake proc/sys
    setup_fake_procsys

    # Add CNI to PATH
    export PATH=$PATH:/usr/lib/cni

    # Create log directory
    mkdir -p "$K3S_LOG_DIR"

    # Clean up old data directory
    if [ -d "$K3S_DATA_DIR" ]; then
        log_info "Removing old k3s data directory..."
        rm -rf "$K3S_DATA_DIR"
    fi

    # Start k3s with ptrace interceptor
    log_info "Launching k3s server with ptrace interceptor..."
    log_info "Data directory: $K3S_DATA_DIR"
    log_info "Logs: $K3S_LOG_DIR/k3s-{stdout,stderr}.log"

    nohup "$INTERCEPTOR_BIN" /usr/local/bin/k3s server \
        --https-listen-port 6443 \
        --data-dir "$K3S_DATA_DIR" \
        --snapshotter=fuse-overlayfs \
        > "$K3S_LOG_DIR/k3s-stdout.log" \
        2> "$K3S_LOG_DIR/k3s-stderr.log" &

    K3S_PID=$!
    echo $K3S_PID > "$PIDFILE"

    log_info "K3s started with PID: $K3S_PID"
    log_info "Waiting for k3s to initialize (30 seconds)..."

    sleep 30

    # Check if still running
    if kill -0 $K3S_PID 2>/dev/null; then
        log_info "K3s is running"

        # Check for kubeconfig
        if [ -f "/etc/rancher/k3s/k3s.yaml" ]; then
            log_info "Kubeconfig available at: /etc/rancher/k3s/k3s.yaml"
            log_info "Export: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
        fi

        # Check kubelet status in logs
        if grep -q "Started kubelet" "$K3S_LOG_DIR/k3s-stderr.log" 2>/dev/null; then
            log_info "✓ Kubelet started successfully"
        else
            log_warn "Kubelet may not have started - check logs"
        fi

        # Check for ContainerManager
        if grep -q "Failed to start ContainerManager" "$K3S_LOG_DIR/k3s-stderr.log" 2>/dev/null; then
            log_warn "ContainerManager initialization issue detected"
            log_warn "Check: tail -f $K3S_LOG_DIR/k3s-stderr.log"
        fi

        return 0
    else
        log_error "K3s failed to start - check logs at $K3S_LOG_DIR"
        rm -f "$PIDFILE"
        return 1
    fi
}

# Stop k3s
stop_k3s() {
    log_info "Stopping k3s..."

    if [ -f "$PIDFILE" ]; then
        K3S_PID=$(cat "$PIDFILE")
        if kill -0 $K3S_PID 2>/dev/null; then
            log_info "Killing k3s process: $K3S_PID"
            kill $K3S_PID
            sleep 2

            # Force kill if still running
            if kill -0 $K3S_PID 2>/dev/null; then
                log_warn "Force killing k3s process"
                kill -9 $K3S_PID
            fi
        fi
        rm -f "$PIDFILE"
    fi

    # Clean up any remaining processes
    killall -9 k3s 2>/dev/null || true
    killall -9 ptrace_interceptor 2>/dev/null || true

    log_info "K3s stopped"
}

# Show status
show_status() {
    echo "=== K3s Worker Status ==="
    echo

    if [ -f "$PIDFILE" ]; then
        K3S_PID=$(cat "$PIDFILE")
        if kill -0 $K3S_PID 2>/dev/null; then
            echo -e "${GREEN}Status: RUNNING${NC}"
            echo "PID: $K3S_PID"
            echo "Uptime: $(ps -p $K3S_PID -o etime= | tr -d ' ')"
        else
            echo -e "${RED}Status: STOPPED${NC} (stale PID file)"
            rm -f "$PIDFILE"
        fi
    else
        echo -e "${RED}Status: STOPPED${NC}"
    fi

    echo
    echo "=== Component Status ==="

    if [ -f "$K3S_LOG_DIR/k3s-stderr.log" ]; then
        # Check various components
        if grep -q "Started kubelet" "$K3S_LOG_DIR/k3s-stderr.log"; then
            echo -e "Kubelet: ${GREEN}✓ Started${NC}"
        else
            echo -e "Kubelet: ${RED}✗ Not started${NC}"
        fi

        if grep -q "Container runtime initialized" "$K3S_LOG_DIR/k3s-stderr.log"; then
            echo -e "Container Runtime: ${GREEN}✓ Initialized${NC}"
        else
            echo -e "Container Runtime: ${RED}✗ Not initialized${NC}"
        fi

        if grep -q "Starting CPU manager" "$K3S_LOG_DIR/k3s-stderr.log"; then
            echo -e "CPU Manager: ${GREEN}✓ Started${NC}"
        else
            echo -e "CPU Manager: ${YELLOW}⚠ Not started${NC}"
        fi

        if grep -q "Starting memorymanager" "$K3S_LOG_DIR/k3s-stderr.log"; then
            echo -e "Memory Manager: ${GREEN}✓ Started${NC}"
        else
            echo -e "Memory Manager: ${YELLOW}⚠ Not started${NC}"
        fi

        if grep -q "Failed to start ContainerManager" "$K3S_LOG_DIR/k3s-stderr.log"; then
            ERROR=$(grep "Failed to start ContainerManager" "$K3S_LOG_DIR/k3s-stderr.log" | tail -1)
            echo -e "ContainerManager: ${YELLOW}⚠ Issues detected${NC}"
            echo "  Last error: $(echo $ERROR | cut -d'"' -f4)"
        fi
    fi

    echo
    echo "=== Logs ==="
    echo "stdout: $K3S_LOG_DIR/k3s-stdout.log"
    echo "stderr: $K3S_LOG_DIR/k3s-stderr.log"

    if [ -f "/etc/rancher/k3s/k3s.yaml" ]; then
        echo
        echo "=== Kubeconfig ==="
        echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
    fi
}

# Clean up everything
clean_all() {
    log_info "Cleaning up k3s installation..."

    stop_k3s

    log_info "Removing data directories..."
    rm -rf "$K3S_DATA_DIR"
    rm -rf "$K3S_LOG_DIR"
    rm -rf "$FAKE_PROCSYS_DIR"
    rm -f "$PIDFILE"
    rm -f /etc/rancher/k3s/k3s.yaml 2>/dev/null || true

    log_info "Cleanup complete"
}

# Show usage
usage() {
    cat << EOF
K3s Worker Setup for gVisor Sandbox

Usage: $0 <command>

Commands:
    build       Build the ptrace interceptor
    run         Start k3s with worker functionality
    stop        Stop k3s
    status      Show k3s status and component health
    clean       Stop k3s and remove all data
    logs        Tail the k3s logs
    help        Show this help message

Environment:
    K3S_DATA_DIR      Data directory (default: /tmp/k3s-data-gvisor)
    K3S_LOG_DIR       Log directory (default: /tmp/k3s-logs)

Examples:
    # First time setup
    $0 build
    $0 run

    # Check status
    $0 status

    # View logs
    $0 logs

    # Clean restart
    $0 clean
    $0 run
EOF
}

# Tail logs
tail_logs() {
    if [ -f "$K3S_LOG_DIR/k3s-stderr.log" ]; then
        log_info "Tailing k3s logs (Ctrl+C to exit)..."
        tail -f "$K3S_LOG_DIR/k3s-stderr.log"
    else
        log_error "No logs found at $K3S_LOG_DIR/k3s-stderr.log"
        exit 1
    fi
}

# Main command dispatcher
case "${1:-help}" in
    build)
        build_interceptor
        ;;
    run)
        check_gvisor
        check_prerequisites
        start_k3s
        ;;
    stop)
        stop_k3s
        ;;
    status)
        show_status
        ;;
    clean)
        clean_all
        ;;
    logs)
        tail_logs
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        log_error "Unknown command: $1"
        echo
        usage
        exit 1
        ;;
esac

