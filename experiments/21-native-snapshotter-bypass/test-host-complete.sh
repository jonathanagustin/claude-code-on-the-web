#!/bin/bash
# Experiment 21 Phase 3: Complete test with all workarounds
#
# Tests native snapshotter on host with:
# - /dev/kmsg workaround
# - --flannel-backend=none (no CNI plugins needed)
# - --snapshotter=native (bypass overlayfs requirement)

set -e

echo "================================================"
echo "Experiment 21 Phase 3: Complete Host Test"
echo "================================================"
echo ""

# Clean up any existing k3s
pkill k3s 2>/dev/null || true
sleep 2

# Apply /dev/kmsg workaround (from KinD)
echo "Applying /dev/kmsg workaround..."
if [ ! -e /dev/kmsg ]; then
    touch /dev/kmsg
fi
mount --bind /dev/null /dev/kmsg 2>/dev/null || true

echo "Starting k3s with complete configuration..."
echo "  - --snapshotter=native (bypass overlayfs)"
echo "  - --flannel-backend=none (skip CNI requirement)"
echo "  - /dev/kmsg workaround applied"
echo ""

# Start k3s with all workarounds
nohup k3s server \
  --snapshotter=native \
  --flannel-backend=none \
  --data-dir=/tmp/k3s-exp21-complete \
  --kubelet-arg="--image-gc-high-threshold=100" \
  --kubelet-arg="--image-gc-low-threshold=99" \
  > /tmp/k3s-exp21-complete.log 2>&1 &

K3S_PID=$!
echo "Started k3s (PID: $K3S_PID)"
echo "Waiting 60 seconds for initialization..."
sleep 60

echo ""
echo "=== Process Status ==="
if ps aux | grep "[k]3s server" > /dev/null; then
    echo "✅ k3s process is running"
    ps aux | grep "[k]3s server" | head -2
else
    echo "❌ k3s process not found"
fi

echo ""
echo "=== Checking for overlayfs errors ==="
if grep -i "overlayfs.*failed\|operation not permitted.*overlay" /tmp/k3s-exp21-complete.log; then
    echo "❌ Has overlayfs errors"
else
    echo "✅ No overlayfs errors!"
fi

echo ""
echo "=== Checking for /dev/kmsg errors ==="
if grep -i "no such device or address.*kmsg\|failed.*kmsg" /tmp/k3s-exp21-complete.log; then
    echo "❌ Has /dev/kmsg errors"
else
    echo "✅ No /dev/kmsg errors!"
fi

echo ""
echo "=== Checking for CNI errors ==="
if grep -i "failed to find host-local" /tmp/k3s-exp21-complete.log | tail -3; then
    echo "❌ Has CNI errors"
else
    echo "✅ No CNI errors!"
fi

echo ""
echo "=== Cluster Status ==="
if grep -i "k3s is up and running" /tmp/k3s-exp21-complete.log; then
    echo "✅ k3s reported 'up and running'"
fi

if grep -i "node.*ready" /tmp/k3s-exp21-complete.log | tail -3; then
    echo "✅ Node became ready"
fi

echo ""
echo "=== Testing kubectl ==="
export KUBECONFIG=/tmp/k3s-exp21-complete/server/cred/admin.kubeconfig
if kubectl get nodes --insecure-skip-tls-verify 2>&1; then
    echo "✅ kubectl works!"
else
    echo "⚠ kubectl not responding yet"
fi

echo ""
echo "=== Last 30 log lines (filtered) ==="
tail -30 /tmp/k3s-exp21-complete.log | grep -v "^I1123\|^W1123"

echo ""
echo "================================================"
echo "Experiment 21 Phase 3 Results"
echo "================================================"
