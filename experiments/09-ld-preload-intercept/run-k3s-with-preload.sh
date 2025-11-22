#!/bin/bash
#
# Run k3s with LD_PRELOAD interceptor
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "Experiment 09: LD_PRELOAD Interception"
echo "========================================="
echo ""
echo "Approach: Library-level interception (bypasses gVisor kernel)"
echo "  - Intercepts open(), stat(), statfs() at libc level"
echo "  - Redirects /sys/fs/cgroup → /tmp/fake-cgroup"
echo "  - Spoofs 9p filesystem as ext4"
echo ""

# Setup fake files
echo "[INFO] Setting up fake cgroup and proc files..."
./setup-fake-cgroups.sh

# Setup /dev/kmsg workaround
echo "[INFO] Setting up /dev/kmsg workaround..."
touch /dev/kmsg 2>/dev/null || true
mount --bind /dev/null /dev/kmsg 2>/dev/null || true

# Setup mount propagation
echo "[INFO] Configuring mount propagation..."
unshare --mount --propagation unchanged bash -c 'mount --make-rshared /' 2>/dev/null || true

# Setup fake CNI plugin (from Experiment 05)
echo "[INFO] Setting up fake CNI plugin..."
mkdir -p /opt/cni/bin
cat > /opt/cni/bin/host-local << 'EOFCNI'
#!/bin/bash
echo '{"cniVersion": "0.4.0", "ips": [{"version": "4", "address": "10.244.0.1/24"}]}'
exit 0
EOFCNI
chmod +x /opt/cni/bin/host-local

# Kill existing k3s
echo "[INFO] Cleaning up existing k3s processes..."
pkill -9 k3s 2>/dev/null || true
sleep 2

# Remove old data
echo "[INFO] Cleaning k3s state..."
rm -rf /var/lib/rancher/k3s/data /var/lib/rancher/k3s/server/db /run/k3s 2>/dev/null || true

echo ""
echo "[INFO] Starting k3s with LD_PRELOAD interceptor..."
echo "[INFO] Logs: /tmp/exp09-k3s.log"
echo ""
echo "Expected behavior:"
echo "  ✓ cAdvisor sees ext4 instead of 9p"
echo "  ✓ cgroup files readable from /tmp/fake-cgroup"
echo "  ✓ Worker node starts successfully"
echo "  ✓ Node becomes Ready"
echo ""

export PATH="/opt/cni/bin:$PATH"
export LD_PRELOAD="$SCRIPT_DIR/ld_preload_interceptor.so"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

/usr/local/bin/k3s server \
    --snapshotter=native \
    --kubelet-arg=--fail-swap-on=false \
    --kubelet-arg=--image-gc-high-threshold=100 \
    --kubelet-arg=--image-gc-low-threshold=99 \
    --kubelet-arg=--cgroups-per-qos=false \
    --kubelet-arg=--enforce-node-allocatable= \
    --disable=coredns,servicelb,traefik,local-storage,metrics-server \
    --write-kubeconfig-mode=644 \
    > /tmp/exp09-k3s.log 2>&1 &

K3S_PID=$!
echo "[INFO] k3s started with PID $K3S_PID"
echo ""

# Wait for k3s to start
echo "[INFO] Waiting 45 seconds for k3s initialization..."
sleep 45

# Check if k3s is still running
if ps -p $K3S_PID > /dev/null 2>&1; then
    echo "[SUCCESS] k3s is still running after 45 seconds!"
    echo ""

    # Try to query the cluster
    echo "[INFO] Checking cluster status..."
    kubectl --insecure-skip-tls-verify get nodes 2>&1 || true
    echo ""

    # Check for cAdvisor errors
    echo "[INFO] Checking for cAdvisor errors..."
    if grep -q "unable to find data in memory cache" /tmp/exp09-k3s.log; then
        echo "[FAIL] Still seeing cAdvisor error"
    else
        echo "[SUCCESS] No cAdvisor 'unable to find data' error!"
    fi

    # Check for interceptor activity
    echo ""
    echo "[INFO] LD_PRELOAD interception activity:"
    grep -c "LD_PRELOAD" /tmp/exp09-k3s.log || echo "  No interceptions logged"

else
    echo "[FAIL] k3s exited early"
    echo ""
    echo "Last 50 lines of log:"
    tail -50 /tmp/exp09-k3s.log
fi
