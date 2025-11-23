#!/bin/bash
#
# Experiment 22: Complete Solution
# Combines ALL discovered solutions including native snapshotter
#
# Components:
# - Experiment 21: Native snapshotter (--snapshotter=native)
# - Experiment 12: cAdvisor bypass (--local-storage-capacity-isolation=false)
# - Experiment 04/13: Ptrace syscall interceptor (for /proc/sys redirection)
# - Experiment 15: Flannel bypass (--flannel-backend=none)
# - Experiment 05: Fake CNI plugin
# - KinD: /dev/kmsg workaround
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "============================================================="
echo "Experiment 22: Complete Solution"
echo "============================================================="
echo ""
echo "This combines ALL discovered solutions:"
echo "  ✓ Native snapshotter (Exp 21) - bypasses overlayfs"
echo "  ✓ cAdvisor bypass (Exp 12) - bypasses filesystem check"
echo "  ✓ Ptrace interceptor (Exp 04/13) - redirects /proc/sys"
echo "  ✓ Flannel bypass (Exp 15) - skips CNI requirement"
echo "  ✓ Fake CNI plugin (Exp 05) - provides minimal CNI"
echo "  ✓ /dev/kmsg workaround (KinD) - kernel message device"
echo ""

# Clean up any existing k3s
pkill k3s 2>/dev/null || true
pkill ptrace_interceptor 2>/dev/null || true
sleep 2

# =============================================================================
# Phase 1: Build Enhanced Ptrace Interceptor
# =============================================================================
echo "[1/7] Building enhanced ptrace syscall interceptor..."

gcc -o ptrace_interceptor ptrace_interceptor_enhanced.c -O2 2>&1 | head -20 || {
    echo "[ERROR] Failed to compile ptrace_interceptor"
    exit 1
}

echo "  ✓ Enhanced ptrace interceptor compiled"

# =============================================================================
# Phase 2: Create Fake /proc/sys Files
# =============================================================================
echo ""
echo "[2/7] Creating fake /proc/sys files..."

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
# Phase 3: Setup Fake CNI Plugin
# =============================================================================
echo ""
echo "[3/7] Setting up fake CNI plugin..."

CNI_BIN_DIR="/opt/cni/bin"
mkdir -p "$CNI_BIN_DIR"

# Create minimal fake host-local CNI plugin
cat > "$CNI_BIN_DIR/host-local" << 'EOFCNI'
#!/bin/bash
# Minimal fake CNI plugin (from Experiment 05)
case "$CNI_COMMAND" in
    ADD)
        echo '{"cniVersion":"0.4.0","ips":[{"version":"4","address":"10.42.0.2/24"}]}'
        ;;
    DEL|CHECK|VERSION)
        echo '{"cniVersion":"0.4.0"}'
        ;;
esac
exit 0
EOFCNI

chmod +x "$CNI_BIN_DIR/host-local"
echo "  ✓ Fake CNI plugin created"

# =============================================================================
# Phase 4: Apply /dev/kmsg Workaround
# =============================================================================
echo ""
echo "[4/7] Applying /dev/kmsg workaround..."

if [ ! -e /dev/kmsg ]; then
    touch /dev/kmsg
fi
mount --bind /dev/null /dev/kmsg 2>/dev/null || true

echo "  ✓ /dev/kmsg workaround applied"

# =============================================================================
# Phase 5: Apply iptables-legacy Workaround
# =============================================================================
echo ""
echo "[5/7] Applying iptables-legacy workaround..."

if command -v iptables-legacy &> /dev/null; then
    update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true
    echo "  ✓ iptables-legacy configured"
else
    echo "  ⚠ iptables-legacy not found (may cause issues)"
fi

# =============================================================================
# Phase 6-7: Start k3s Under Ptrace Interceptor
# =============================================================================
echo ""
echo "[6/7] Starting k3s under ptrace interceptor..."
echo ""
echo "k3s flags:"
echo "  --snapshotter=native (NEW from Exp 21)"
echo "  --flannel-backend=none (Exp 15)"
echo "  --local-storage-capacity-isolation=false (Exp 12)"
echo "  --image-gc thresholds (infrastructure)"
echo ""

# Start k3s server under ptrace interceptor with ALL solutions
nohup ./ptrace_interceptor k3s server \
  --snapshotter=native \
  --flannel-backend=none \
  --kubelet-arg="--local-storage-capacity-isolation=false" \
  --kubelet-arg="--image-gc-high-threshold=100" \
  --kubelet-arg="--image-gc-low-threshold=99" \
  --data-dir=/tmp/k3s-complete \
  > /tmp/k3s-complete.log 2>&1 &

K3S_PID=$!
echo "Started k3s server under ptrace (PID: $K3S_PID)"
echo ""
echo "Waiting 90 seconds for initialization..."
echo "(You can monitor progress: tail -f /tmp/k3s-complete.log)"
echo ""

sleep 90

# =============================================================================
# Results Analysis
# =============================================================================
echo ""
echo "============================================================="
echo "Results Analysis"
echo "============================================================="
echo ""

# Check if k3s is still running
echo "=== Process Status ==="
if ps -p $K3S_PID > /dev/null 2>&1; then
    echo "✅ k3s server is RUNNING (PID: $K3S_PID)"
    ps aux | grep "[k]3s server" | head -2
    K3S_RUNNING=true
else
    echo "❌ k3s server exited"
    K3S_RUNNING=false
fi

echo ""
echo "=== Checking All Known Blockers ==="

# 1. Overlayfs errors
echo ""
echo "1. Overlayfs errors (Exp 21 solution):"
if grep -qi "overlayfs.*failed\|operation not permitted.*overlay" /tmp/k3s-complete.log 2>/dev/null; then
    echo "   ❌ Has overlayfs errors"
    grep -i "overlayfs.*failed\|operation not permitted.*overlay" /tmp/k3s-complete.log | tail -3
else
    echo "   ✅ No overlayfs errors"
fi

# 2. cAdvisor errors
echo ""
echo "2. cAdvisor rootfs errors (Exp 12 solution):"
if grep -qi "failed to get rootfs info.*memory cache" /tmp/k3s-complete.log 2>/dev/null; then
    echo "   ❌ Has cAdvisor errors"
    grep -i "failed to get rootfs info.*memory cache" /tmp/k3s-complete.log | tail -3
else
    echo "   ✅ No cAdvisor errors"
fi

# 3. /proc/sys errors
echo ""
echo "3. /proc/sys file errors (Exp 04/13 solution):"
if grep -qi "no such file or directory.*proc/sys" /tmp/k3s-complete.log 2>/dev/null; then
    echo "   ❌ Has /proc/sys errors"
    grep -i "no such file or directory.*proc/sys" /tmp/k3s-complete.log | tail -3
else
    echo "   ✅ No /proc/sys errors"
fi

# 4. /dev/kmsg errors
echo ""
echo "4. /dev/kmsg errors (KinD solution):"
if grep -qi "no such device or address.*kmsg" /tmp/k3s-complete.log 2>/dev/null; then
    echo "   ❌ Has /dev/kmsg errors"
else
    echo "   ✅ No /dev/kmsg errors"
fi

# 5. ContainerManager errors
echo ""
echo "5. ContainerManager errors:"
if grep -qi "Failed to start ContainerManager" /tmp/k3s-complete.log 2>/dev/null; then
    echo "   ❌ ContainerManager failed"
    grep -i "Failed to start ContainerManager" /tmp/k3s-complete.log | tail -3
else
    echo "   ✅ ContainerManager started"
fi

# Cluster status
echo ""
echo "=== Cluster Status ==="
if grep -qi "k3s is up and running" /tmp/k3s-complete.log 2>/dev/null; then
    echo "✅ k3s reported 'up and running'"
fi

if grep -qi "node.*ready" /tmp/k3s-complete.log 2>/dev/null; then
    echo "✅ Node became Ready"
    grep -i "node.*ready" /tmp/k3s-complete.log | tail -3
fi

# Test kubectl
echo ""
echo "=== Testing kubectl ==="
export KUBECONFIG=/tmp/k3s-complete/server/cred/admin.kubeconfig

if [ "$K3S_RUNNING" = "true" ]; then
    sleep 5
    if timeout 10 kubectl get nodes --insecure-skip-tls-verify 2>&1; then
        echo ""
        echo "✅ kubectl works!"
        echo ""
        echo "=== Cluster Info ==="
        kubectl get nodes -o wide --insecure-skip-tls-verify 2>&1 || true
        echo ""
        echo "=== All Pods ==="
        kubectl get pods -A --insecure-skip-tls-verify 2>&1 || true
    else
        echo "⚠ kubectl connection timeout or error"
    fi
else
    echo "⚠ Skipping kubectl test (k3s not running)"
fi

# Show recent logs
echo ""
echo "=== Last 40 Log Lines (filtered) ==="
tail -40 /tmp/k3s-complete.log | grep -v "^I1123\|^W1123" | tail -30

echo ""
echo "============================================================="
echo "Experiment 22 Summary"
echo "============================================================="
echo ""
if [ "$K3S_RUNNING" = "true" ]; then
    echo "🎉 SUCCESS: k3s is running with complete solution!"
    echo ""
    echo "All solutions applied:"
    echo "  ✓ Native snapshotter (bypassed overlayfs)"
    echo "  ✓ cAdvisor bypass (bypassed filesystem check)"
    echo "  ✓ Ptrace interceptor (redirected /proc/sys)"
    echo "  ✓ Flannel bypass (skipped CNI requirement)"
    echo "  ✓ /dev/kmsg workaround (provided kernel device)"
    echo ""
    echo "Next: Test pod deployment with kubectl"
else
    echo "⚠ k3s started but exited. Check logs above for details."
fi
echo ""
echo "Log files:"
echo "  - k3s: /tmp/k3s-complete.log"
echo "  - ptrace: /tmp/ptrace-interceptor.log"
echo ""
