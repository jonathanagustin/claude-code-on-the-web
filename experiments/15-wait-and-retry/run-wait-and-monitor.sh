#!/bin/bash
#
# Experiment 15: Wait and Monitor
# Test if k3s stabilizes AFTER the initial post-start hook panic
#
# Strategy:
# - Start k3s and let it run
# - Monitor every 30 seconds for 5 minutes
# - Check if k3s continues running after panic
# - Attempt kubectl operations at each check
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "Experiment 15: Wait and Monitor"
echo "========================================="
echo ""
echo "Question: Does k3s stabilize AFTER the post-start hook panic?"
echo ""
echo "Strategy:"
echo "  - Start k3s in background"
echo "  - Monitor every 30s for 5 minutes"
echo "  - Check if process continues running"
echo "  - Attempt kubectl operations"
echo ""

# Build interceptor
echo "[1/5] Building ptrace interceptor..."
gcc -o ptrace_interceptor ptrace_interceptor_enhanced.c -O2 || {
    echo "[ERROR] Failed to compile"
    exit 1
}
echo "  ✓ Compiled"

# Create fake files
echo ""
echo "[2/5] Creating fake /proc/sys files..."
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

echo "1" > "$FAKE_PROCSYS/vm/panic_on_oom"
echo "10" > "$FAKE_PROCSYS/kernel/panic"
echo "1" > "$FAKE_PROCSYS/kernel/panic_on_oops"
echo "1000000" > "$FAKE_PROCSYS/kernel/keys/root_maxkeys"
echo "25000000" > "$FAKE_PROCSYS/kernel/keys/root_maxbytes"
echo "1" > "$FAKE_PROCSYS/vm/overcommit_memory"
echo "65536" > "$FAKE_PROCSYS/kernel/pid_max"
echo "1" > "$FAKE_PROCSYS/net/ipv4/conf/all/route_localnet"
echo "1" > "$FAKE_PROCSYS/net/ipv4/ip_forward"
echo "1" > "$FAKE_PROCSYS/net/bridge/bridge-nf-call-iptables"
echo "0" > "$FAKE_PROCSYS/net/ipv4/conf/all/rp_filter"
echo "0" > "$FAKE_PROCSYS/net/ipv4/conf/default/rp_filter"
echo "0" > "$FAKE_PROCSYS/net/ipv6/conf/all/forwarding"
echo "  ✓ Created"

# Setup CNI
echo ""
echo "[3/5] Setting up fake CNI..."
mkdir -p /opt/cni/bin
cat > /opt/cni/bin/host-local << 'EOFCNI'
#!/bin/bash
echo '{"cniVersion": "0.4.0", "ips": [{"version": "4", "address": "10.244.0.1/24"}]}'
exit 0
EOFCNI
chmod +x /opt/cni/bin/host-local
export PATH="/opt/cni/bin:$PATH"
echo "  ✓ Installed"

# Cleanup
echo ""
echo "[4/5] Cleaning up..."
pkill -9 k3s 2>/dev/null || true
pkill -9 ptrace_interceptor 2>/dev/null || true
sleep 2
rm -rf /var/lib/rancher/k3s/data /var/lib/rancher/k3s/server/db /run/k3s 2>/dev/null || true
echo "  ✓ Clean"

# Start k3s
echo ""
echo "[5/5] Starting k3s..."
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

./ptrace_interceptor /usr/local/bin/k3s server \
    --snapshotter=native \
    --flannel-backend=none \
    --kubelet-arg=--fail-swap-on=false \
    --kubelet-arg=--cgroups-per-qos=false \
    --kubelet-arg=--enforce-node-allocatable= \
    --kubelet-arg=--local-storage-capacity-isolation=false \
    --kubelet-arg=--protect-kernel-defaults=false \
    --kubelet-arg=--image-gc-high-threshold=100 \
    --kubelet-arg=--image-gc-low-threshold=99 \
    --disable=coredns,servicelb,traefik,local-storage,metrics-server \
    --write-kubeconfig-mode=644 \
    > /tmp/exp15-k3s.log 2>&1 &

K3S_PID=$!
echo "  ✓ Started (PID $K3S_PID)"
echo ""

# Monitor function
check_k3s() {
    local elapsed=$1
    echo "================================================"
    echo "Check at ${elapsed}s"
    echo "================================================"

    # Check if process is running
    if ps -p $K3S_PID > /dev/null 2>&1; then
        echo "✅ k3s process STILL RUNNING (PID $K3S_PID)"

        # Try kubectl
        echo ""
        echo "Testing kubectl operations..."
        if kubectl get nodes --insecure-skip-tls-verify 2>/dev/null; then
            echo "✅ kubectl get nodes WORKS!"
        else
            echo "⏳ kubectl get nodes not ready yet"
        fi

        if kubectl get pods -A --insecure-skip-tls-verify 2>/dev/null; then
            echo "✅ kubectl get pods WORKS!"
        else
            echo "⏳ kubectl get pods not ready yet"
        fi

        # Check for panic in logs
        if grep -q "PostStartHook.*failed" /tmp/exp15-k3s.log; then
            echo "⚠️  Post-start hook panic occurred (but process continues!)"
        fi

        return 0
    else
        echo "❌ k3s process EXITED"
        echo ""
        echo "Last 30 lines of log:"
        tail -30 /tmp/exp15-k3s.log
        return 1
    fi
}

# Monitoring loop
echo "========================================="
echo "Monitoring k3s for 5 minutes..."
echo "========================================="
echo ""

for i in {1..10}; do
    elapsed=$((i * 30))
    sleep 30

    if ! check_k3s $elapsed; then
        echo ""
        echo "========================================="
        echo "RESULT: k3s exited at ${elapsed}s"
        echo "========================================="
        exit 1
    fi
    echo ""
done

# Final check
echo "========================================="
echo "FINAL RESULT (after 5 minutes)"
echo "========================================="
echo ""

if ps -p $K3S_PID > /dev/null 2>&1; then
    echo "🎉 SUCCESS! k3s has been running for 5 minutes!"
    echo ""
    echo "Final status:"
    kubectl get nodes --insecure-skip-tls-verify
    echo ""
    kubectl get pods -A --insecure-skip-tls-verify
    echo ""
    echo "✅ k3s is STABLE and FUNCTIONAL!"
    echo ""
    echo "To continue monitoring: tail -f /tmp/exp15-k3s.log"
    echo "To use cluster: kubectl --insecure-skip-tls-verify get nodes"
else
    echo "❌ k3s exited before 5 minutes"
    tail -50 /tmp/exp15-k3s.log
fi
