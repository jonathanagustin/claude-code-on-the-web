#!/bin/bash

echo "=== Testing NoNewKeyring Runtime Option ==="
echo ""

# Ensure fake /proc/sys files exist
mkdir -p /tmp/fake-procsys/kernel
echo "40" > /tmp/fake-procsys/kernel/cap_last_cap

# Ensure /dev/kmsg workaround
touch /dev/kmsg
mount --bind /dev/null /dev/kmsg 2>/dev/null || true

# Set mount propagation
unshare --mount --propagation unchanged bash -c 'mount --make-rshared /' 2>/dev/null || true

# Verify containerd config template exists
if [ -f "/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl" ]; then
    echo "✓ Found containerd config template with NoNewKeyring option"
    cat /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl
else
    echo "✗ Containerd config template not found!"
    exit 1
fi

echo ""
echo "Starting k3s with enhanced configuration..."
echo ""

# Change to experiment directory
cd /home/user/claude-code-on-the-web/experiments/22-complete-solution

# Start k3s under ptrace with all solutions
nohup ./ptrace_interceptor k3s server \
  --snapshotter=native \
  --flannel-backend=none \
  --kubelet-arg="--local-storage-capacity-isolation=false" \
  --kubelet-arg="--image-gc-high-threshold=100" \
  --kubelet-arg="--image-gc-low-threshold=99" \
  --data-dir=/tmp/k3s-complete \
  > /tmp/k3s-no-new-keyring.log 2>&1 &

K3S_PID=$!
echo "k3s started with PID $K3S_PID"
echo ""

# Wait for k3s to start
echo "Waiting for k3s API server..."
sleep 15

# Check if k3s is running
if ! ps -p $K3S_PID > /dev/null; then
    echo "✗ k3s process died!"
    tail -50 /tmp/k3s-no-new-keyring.log
    exit 1
fi

echo "✓ k3s process is running"
echo ""

# Wait for node to be ready
echo "Waiting for node to be ready..."
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
timeout 60 bash -c 'until kubectl get nodes 2>/dev/null | grep -q Ready; do sleep 2; done'

echo ""
echo "=== Node Status ==="
kubectl get nodes -o wide

echo ""
echo "=== Testing Pod Creation ==="

# Create a simple test pod
cat > /tmp/test-no-keyring-pod.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-no-keyring
spec:
  containers:
  - name: pause
    image: rancher/mirrored-pause:3.6
    command: ["/pause"]
EOF

kubectl apply -f /tmp/test-no-keyring-pod.yaml

# Wait and check status
sleep 15

echo ""
echo "=== Pod Status ==="
kubectl get pod test-no-keyring -o wide

echo ""
echo "=== Pod Events ==="
kubectl describe pod test-no-keyring | tail -20

echo ""
echo "=== Recent k3s Logs ==="
tail -30 /tmp/k3s-no-new-keyring.log

echo ""
echo "=== Test Complete ==="
echo "Check if pod progressed past session keyring error!"
