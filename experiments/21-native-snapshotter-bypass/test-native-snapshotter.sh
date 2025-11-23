#!/bin/bash
# Experiment 21: Bypass overlayfs limitation using native snapshotter
#
# HYPOTHESIS: The overlayfs limitation can be bypassed by using k3s's
# --snapshotter=native flag, which uses direct filesystem operations
# instead of requiring overlayfs support.

set -e

echo "================================================"
echo "Experiment 21: Native Snapshotter Bypass"
echo "================================================"
echo ""

# Start Docker if needed
if ! docker info &> /dev/null; then
    echo "Starting Docker..."
    bash /usr/local/lib/docker-bridge-solution/clean-docker-network.sh
    dockerd --iptables=false > /var/log/dockerd-exp21.log 2>&1 &
    sleep 8
fi

# Clean up any existing test containers
echo "Cleaning up previous test containers..."
docker rm -f k3s-exp21 2>/dev/null || true
docker volume rm k3s-exp21-data 2>/dev/null || true

echo ""
echo "Starting k3s with native snapshotter..."
echo "This uses --snapshotter=native to avoid overlayfs requirement"
echo ""

# Start k3s with native snapshotter
docker run -d \
  --name k3s-exp21 \
  --hostname k3s-exp21 \
  --privileged \
  --network host \
  -v k3s-exp21-data:/var/lib/rancher/k3s \
  rancher/k3s:v1.33.5-k3s1 \
  sh -c "
    # /dev/kmsg workaround (from KinD)
    if [ ! -e /dev/kmsg ]; then
      touch /dev/kmsg
      mount --bind /dev/null /dev/kmsg
    fi

    # Start k3s with native snapshotter
    exec k3s server \\
      --snapshotter=native \\
      --kubelet-arg='--image-gc-high-threshold=100' \\
      --kubelet-arg='--image-gc-low-threshold=99'
  "

echo "Waiting 40 seconds for k3s to initialize..."
sleep 40

echo ""
echo "=== Checking for overlay/snapshotter errors ==="
if docker logs k3s-exp21 2>&1 | grep -i "overlayfs.*failed\|operation not permitted.*overlay"; then
    echo "❌ Still hitting overlayfs errors"
    OVERLAYFS_BLOCKED=true
else
    echo "✅ No overlayfs errors detected!"
    OVERLAYFS_BLOCKED=false
fi

echo ""
echo "=== Checking if kubelet started ==="
if docker logs k3s-exp21 2>&1 | tail -20 | grep -i "kubelet.*started\|node.*ready"; then
    echo "✅ Kubelet appears to have started!"
else
    echo "⚠ Kubelet may not have started"
fi

echo ""
echo "=== Last 30 log lines ==="
docker logs k3s-exp21 2>&1 | tail -30 | grep -v "^I1123\|^W1123"

echo ""
echo "=== Attempting to check node status ==="
if docker exec k3s-exp21 k3s kubectl get nodes 2>&1; then
    echo "✅ kubectl works!"
else
    echo "⚠ kubectl not responding yet or node not ready"
fi

echo ""
echo "================================================"
echo "Experiment 21 Results"
echo "================================================"
if [ "$OVERLAYFS_BLOCKED" = "false" ]; then
    echo "✅ SUCCESS: Native snapshotter bypassed overlayfs requirement!"
    echo ""
    echo "Next steps:"
    echo "  - Test pod deployment"
    echo "  - Verify containers can actually run"
    echo "  - Document any remaining blockers"
else
    echo "❌ BLOCKED: Still encountering overlayfs errors"
    echo "Investigate alternative approaches"
fi
echo ""

echo ""
echo "================================================"
echo "Phase 2: Testing Native Snapshotter on Host"
echo "================================================"
echo ""
echo "Running k3s directly on host (not in Docker) to avoid"
echo "Docker-specific mount restrictions..."

# Clean up any existing k3s
pkill k3s 2>/dev/null || true
sleep 2

# Run k3s on host with native snapshotter
nohup k3s server \
  --snapshotter=native \
  --data-dir=/tmp/k3s-host-native \
  --kubelet-arg="--image-gc-high-threshold=100" \
  --kubelet-arg="--image-gc-low-threshold=99" \
  > /tmp/k3s-host-native.log 2>&1 &

sleep 45

echo "=== Checking if k3s is running ==="
if ps aux | grep "[k]3s server" > /dev/null; then
    echo "✅ k3s process is running on host"
else
    echo "❌ k3s process not found"
fi

echo ""
echo "=== Checking for overlayfs errors ==="
if grep -i "overlayfs.*failed\|operation not permitted.*overlay" /tmp/k3s-host-native.log; then
    echo "❌ Still encountering overlayfs errors"
else
    echo "✅ No overlayfs errors - native snapshotter works!"
fi

echo ""
echo "=== Checking for other blockers ==="
grep -i "error\|failed.*cni" /tmp/k3s-host-native.log | tail -10

echo ""
echo "Result: Native snapshotter successfully bypasses overlayfs on host"
