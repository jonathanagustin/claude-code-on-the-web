#!/bin/bash
#
# Experiment 13: Ultimate Solution
# Combines ALL working techniques from previous experiments
#
# Components:
# - Experiment 04: Ptrace syscall interceptor (for /proc/sys redirection)
# - Experiment 05: Fake CNI plugin
# - Experiment 12: --local-storage-capacity-isolation=false flag
# - All infrastructure workarounds
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "Experiment 13: Ultimate Solution"
echo "========================================="
echo ""
echo "Strategy: Combine ALL working techniques"
echo "  ✓ Ptrace for /proc/sys redirection (Exp 04)"
echo "  ✓ Fake CNI plugin (Exp 05)"
echo "  ✓ --local-storage-capacity-isolation=false (Exp 12)"
echo "  ✓ All infrastructure workarounds"
echo ""

# =============================================================================
# Phase 1: Build Enhanced Ptrace Interceptor
# =============================================================================
echo "[1/6] Building enhanced ptrace syscall interceptor..."

gcc -o ptrace_interceptor ptrace_interceptor_enhanced.c -O2 2>&1 | head -20 || {
    echo "[ERROR] Failed to compile ptrace_interceptor"
    exit 1
}

echo "  ✓ Enhanced ptrace interceptor compiled (includes /proc/sys/net/*)"

# =============================================================================
# Phase 2: Create Fake /proc/sys Files
# =============================================================================
echo ""
echo "[2/6] Creating fake /proc/sys files..."

FAKE_PROCSYS="/tmp/fake-procsys"
rm -rf "$FAKE_PROCSYS"
mkdir -p "$FAKE_PROCSYS/kernel/keys"
mkdir -p "$FAKE_PROCSYS/vm"
mkdir -p "$FAKE_PROCSYS/net/ipv4/conf/all"
mkdir -p "$FAKE_PROCSYS/net/ipv4/conf/default"
mkdir -p "$FAKE_PROCSYS/net/ipv4"
mkdir -p "$FAKE_PROCSYS/net/ipv6/conf/all"
mkdir -p "$FAKE_PROCSYS/net/ipv6/conf/default"
mkdir -p "$FAKE_PROCSYS/net/bridge"

# Create files kubelet needs
echo "1" > "$FAKE_PROCSYS/vm/panic_on_oom"
echo "10" > "$FAKE_PROCSYS/kernel/panic"
echo "1" > "$FAKE_PROCSYS/kernel/panic_on_oops"
echo "1000000" > "$FAKE_PROCSYS/kernel/keys/root_maxkeys"
echo "25000000" > "$FAKE_PROCSYS/kernel/keys/root_maxbytes"
echo "1" > "$FAKE_PROCSYS/vm/overcommit_memory"
echo "65536" > "$FAKE_PROCSYS/kernel/pid_max"

# Create files kube-proxy needs
echo "1" > "$FAKE_PROCSYS/net/ipv4/conf/all/route_localnet"
echo "1" > "$FAKE_PROCSYS/net/ipv4/ip_forward"
echo "1" > "$FAKE_PROCSYS/net/bridge/bridge-nf-call-iptables"
echo "0" > "$FAKE_PROCSYS/net/ipv4/conf/all/rp_filter"
echo "0" > "$FAKE_PROCSYS/net/ipv4/conf/default/rp_filter"
echo "0" > "$FAKE_PROCSYS/net/ipv6/conf/all/forwarding"

echo "  ✓ Fake /proc/sys files created"

# =============================================================================
# Phase 3: Setup Fake CNI Plugin (from Experiment 05)
# =============================================================================
echo ""
echo "[3/6] Setting up fake CNI plugin..."

mkdir -p /opt/cni/bin

cat > /opt/cni/bin/host-local << 'EOFCNI'
#!/bin/bash
echo '{"cniVersion": "0.4.0", "ips": [{"version": "4", "address": "10.244.0.1/24"}]}'
exit 0
EOFCNI

chmod +x /opt/cni/bin/host-local
export PATH="/opt/cni/bin:$PATH"

echo "  ✓ Fake CNI plugin installed"

# =============================================================================
# Phase 4: Setup Infrastructure Workarounds
# =============================================================================
echo ""
echo "[4/6] Configuring infrastructure workarounds..."

# /dev/kmsg workaround
touch /dev/kmsg 2>/dev/null || true
mount --bind /dev/null /dev/kmsg 2>/dev/null || echo "  (kmsg already configured)"

# Mount propagation
unshare --mount --propagation unchanged bash -c 'mount --make-rshared /' 2>/dev/null || echo "  (mount propagation already configured)"

echo "  ✓ Infrastructure configured"

# =============================================================================
# Phase 5: Cleanup Existing k3s
# =============================================================================
echo ""
echo "[5/6] Cleaning up existing k3s processes..."

pkill -9 k3s 2>/dev/null || true
pkill -9 ptrace_interceptor 2>/dev/null || true
sleep 2

rm -rf /var/lib/rancher/k3s/data /var/lib/rancher/k3s/server/db /run/k3s 2>/dev/null || true

echo "  ✓ Cleanup complete"

# =============================================================================
# Phase 6: Launch k3s with Ptrace Wrapper
# =============================================================================
echo ""
echo "[6/6] Starting k3s with ptrace wrapper..."
echo ""
echo "Configuration:"
echo "  - Ptrace: Redirects /proc/sys/* → /tmp/fake-procsys/*"
echo "  - CNI: Fake host-local plugin"
echo "  - LocalStorageCapacityIsolation: Disabled"
echo "  - Logs: /tmp/exp13-k3s.log"
echo ""

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Start k3s with ptrace wrapper (verbose mode)
./ptrace_interceptor -v /usr/local/bin/k3s server \
    --snapshotter=native \
    --kubelet-arg=--fail-swap-on=false \
    --kubelet-arg=--cgroups-per-qos=false \
    --kubelet-arg=--enforce-node-allocatable= \
    --kubelet-arg=--local-storage-capacity-isolation=false \
    --kubelet-arg=--protect-kernel-defaults=false \
    --kubelet-arg=--image-gc-high-threshold=100 \
    --kubelet-arg=--image-gc-low-threshold=99 \
    --disable=coredns,servicelb,traefik,local-storage,metrics-server \
    --write-kubeconfig-mode=644 \
    > /tmp/exp13-k3s.log 2>&1 &

K3S_PID=$!
echo "[INFO] k3s started with PID $K3S_PID"
echo ""

# =============================================================================
# Phase 7: Monitor Startup
# =============================================================================
echo "Waiting 60 seconds for k3s initialization..."
sleep 60

echo ""
echo "========================================="
echo "Experiment 13 Results"
echo "========================================="
echo ""

# Check if k3s is running
if ps -p $K3S_PID > /dev/null 2>&1; then
    echo "✅ k3s process is RUNNING (PID $K3S_PID)"
    echo ""

    # Check for cAdvisor error
    if grep -q "unable to find data in memory cache" /tmp/exp13-k3s.log; then
        echo "❌ cAdvisor error STILL PRESENT"
    else
        echo "✅ cAdvisor error ELIMINATED"
    fi

    # Check for /proc/sys errors
    if grep -q "open /proc/sys" /tmp/exp13-k3s.log; then
        echo "❌ /proc/sys errors STILL PRESENT"
    else
        echo "✅ /proc/sys errors ELIMINATED"
    fi

    echo ""
    echo "Checking cluster status..."
    kubectl get nodes --insecure-skip-tls-verify 2>&1 | head -10 || echo "  (API server not ready yet)"

    echo ""
    echo "Last 30 lines of log:"
    tail -30 /tmp/exp13-k3s.log

else
    echo "❌ k3s process EXITED"
    echo ""
    echo "Last 50 lines of log:"
    tail -50 /tmp/exp13-k3s.log
fi

echo ""
echo "========================================="
echo "To monitor: tail -f /tmp/exp13-k3s.log"
echo "To check status: kubectl get nodes --insecure-skip-tls-verify"
echo "========================================="
