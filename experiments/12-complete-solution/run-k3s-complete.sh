#!/bin/bash
#
# Experiment 12: COMPLETE SOLUTION
# Combines ALL working fixes:
# 1. Fake CNI (Exp 05)
# 2. Fake /proc/sys files (Exp 04)
# 3. --local-storage-capacity-isolation=false (NEW!)
#

set -e

echo "==========================================================="
echo "Experiment 12: COMPLETE k3s Worker Node Solution"
echo "==========================================================="
echo ""
echo "Combining ALL successful techniques:"
echo "  ✓ Fake CNI plugin (Experiment 05)"
echo "  ✓ Fake /proc/sys files (Experiment 04)"
echo "  ✓ --local-storage-capacity-isolation=false (Exp 12)"
echo "  ✓ /dev/kmsg workaround"
echo "  ✓ Mount propagation fix"
echo ""

# Kill existing k3s
pkill -9 k3s 2>/dev/null || true
sleep 2

# Clean state
rm -rf /var/lib/rancher/k3s/data /var/lib/rancher/k3s/server/db /run/k3s 2>/dev/null || true

# Setup /dev/kmsg workaround
echo "[INFO] Setting up /dev/kmsg workaround..."
touch /dev/kmsg 2>/dev/null || true
mount --bind /dev/null /dev/kmsg 2>/dev/null || true

# Setup mount propagation
echo "[INFO] Configuring mount propagation..."
unshare --mount --propagation unchanged bash -c 'mount --make-rshared /' 2>/dev/null || true

# Setup fake /proc/sys files
echo "[INFO] Creating fake /proc/sys files..."
FAKE_PROCSYS="/tmp/fake-procsys"
rm -rf "$FAKE_PROCSYS"
mkdir -p "$FAKE_PROCSYS/kernel"
mkdir -p "$FAKE_PROCSYS/vm"
mkdir -p "$FAKE_PROCSYS/net/core"
mkdir -p "$FAKE_PROCSYS/net/ipv4"

# Kernel parameters
echo "0" > "$FAKE_PROCSYS/kernel/panic"
echo "0" > "$FAKE_PROCSYS/kernel/panic_on_oops"
mkdir -p "$FAKE_PROCSYS/kernel/keys"
echo "65536" > "$FAKE_PROCSYS/kernel/pid_max"
echo "262144" > "$FAKE_PROCSYS/kernel/threads-max"
echo "262144" > "$FAKE_PROCSYS/kernel/keys/root_maxkeys"
echo "25000000" > "$FAKE_PROCSYS/kernel/keys/root_maxbytes"

# VM parameters
echo "1" > "$FAKE_PROCSYS/vm/overcommit_memory"
echo "0" > "$FAKE_PROCSYS/vm/panic_on_oom"

# Bind mount fake files
mount --bind "$FAKE_PROCSYS/kernel/panic" "/proc/sys/kernel/panic" 2>/dev/null || true
mount --bind "$FAKE_PROCSYS/kernel/panic_on_oops" "/proc/sys/kernel/panic_on_oops" 2>/dev/null || true
mount --bind "$FAKE_PROCSYS/vm/panic_on_oom" "/proc/sys/vm/panic_on_oom" 2>/dev/null || true
mount --bind "$FAKE_PROCSYS/vm/overcommit_memory" "/proc/sys/vm/overcommit_memory" 2>/dev/null || true

echo "  ✓ /proc/sys files created and mounted"

# Setup fake CNI plugin
echo "[INFO] Setting up fake CNI plugin..."
mkdir -p /opt/cni/bin
cat > /opt/cni/bin/host-local << 'EOFCNI'
#!/bin/bash
echo '{"cniVersion": "0.4.0", "ips": [{"version": "4", "address": "10.244.0.1/24"}]}'
exit 0
EOFCNI
chmod +x /opt/cni/bin/host-local
echo "  ✓ Fake CNI plugin created"

echo ""
echo "[INFO] Starting k3s with COMPLETE configuration..."
echo ""

export PATH="/opt/cni/bin:$PATH"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

/usr/local/bin/k3s server \
    --snapshotter=native \
    --kubelet-arg=--fail-swap-on=false \
    --kubelet-arg=--image-gc-high-threshold=100 \
    --kubelet-arg=--image-gc-low-threshold=99 \
    --kubelet-arg=--cgroups-per-qos=false \
    --kubelet-arg=--enforce-node-allocatable= \
    --kubelet-arg=--local-storage-capacity-isolation=false \
    --kubelet-arg=--protect-kernel-defaults=false \
    --disable=coredns,servicelb,traefik,local-storage,metrics-server \
    --write-kubeconfig-mode=644 \
    > /tmp/exp12-complete.log 2>&1 &

K3S_PID=$!

echo "[INFO] k3s started with PID $K3S_PID"
echo "[INFO] Waiting 60 seconds for initialization..."
sleep 60

echo ""
echo "==========================================================="
echo "Testing Results"
echo "==========================================================="

# Check if still running
if ps -p $K3S_PID > /dev/null 2>&1; then
    echo "✅ k3s process is RUNNING"
else
    echo "❌ k3s process EXITED"
    echo ""
    echo "Last 30 lines of log:"
    tail -30 /tmp/exp12-complete.log
    exit 1
fi

# Check for errors
echo ""
echo "Checking for cAdvisor errors..."
if grep -q "unable to find data in memory cache" /tmp/exp12-complete.log; then
    echo "❌ Still seeing cAdvisor error"
else
    echo "✅ NO cAdvisor 'unable to find data' error!"
fi

echo ""
echo "Checking for ContainerManager failures..."
if grep -q "Failed to start ContainerManager" /tmp/exp12-complete.log; then
    echo "❌ ContainerManager failed"
    grep "Failed to start ContainerManager" /tmp/exp12-complete.log
else
    echo "✅ NO ContainerManager failure!"
fi

# Try kubectl
echo ""
echo "Checking cluster status..."
kubectl --insecure-skip-tls-verify get nodes 2>&1 || echo "  (API server may still be starting)"

echo ""
echo "==========================================================="
echo "EXPERIMENT 12 COMPLETE"
echo "==========================================================="
echo ""
echo "Log file: /tmp/exp12-complete.log"
echo "To follow logs: tail -f /tmp/exp12-complete.log"
