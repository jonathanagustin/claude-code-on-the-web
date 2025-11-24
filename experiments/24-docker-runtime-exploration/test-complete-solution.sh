#!/bin/bash

echo "=== Experiment 24: Complete Solution Test ==="
echo ""

# Stop any existing k3s
pkill -f "k3s server" 2>/dev/null
sleep 3

# Ensure fake /proc/sys files exist
mkdir -p /tmp/fake-procsys/kernel
echo "40" > /tmp/fake-procsys/kernel/cap_last_cap
echo "✓ Fake /proc/sys files ready"

# Ensure /dev/kmsg workaround
touch /dev/kmsg
mount --bind /dev/null /dev/kmsg 2>/dev/null || true
echo "✓ /dev/kmsg workaround applied"

# Set mount propagation
unshare --mount --propagation unchanged bash -c 'mount --make-rshared /' 2>/dev/null || true
echo "✓ Mount propagation set"

# Verify containerd config
if grep -q "NoNewKeyring = true" /tmp/k3s-complete/agent/etc/containerd/config.toml.tmpl; then
    echo "✓ NoNewKeyring configuration present"
fi

if grep -q 'sandbox = "rancher/mirrored-pause:3.6"' /tmp/k3s-complete/agent/etc/containerd/config.toml.tmpl; then
    echo "✓ Sandbox image configuration present"
fi

echo ""
echo "Starting k3s with all workarounds..."
cd /home/user/claude-code-on-the-web/experiments/22-complete-solution

nohup ./ptrace_interceptor k3s server \
  --snapshotter=native \
  --flannel-backend=none \
  --kubelet-arg="--local-storage-capacity-isolation=false" \
  --kubelet-arg="--image-gc-high-threshold=100" \
  --kubelet-arg="--image-gc-low-threshold=99" \
  --data-dir=/tmp/k3s-complete \
  > /tmp/k3s-layer3-test.log 2>&1 &

K3S_PID=$!
echo "k3s started with PID: $K3S_PID"
echo ""

# Wait for k3s to stabilize
echo "Waiting 30 seconds for k3s to stabilize..."
sleep 30

# Check if still running
if ps -p $K3S_PID > /dev/null; then
    echo "✓ k3s process is running"
else
    echo "✗ k3s crashed!"
    echo ""
    echo "=== Error logs ==="
    tail -30 /tmp/k3s-layer3-test.log
    exit 1
fi

# Wait for API server
echo ""
echo "Waiting for API server..."
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
timeout 60 bash -c 'until kubectl get nodes 2>/dev/null; do sleep 2; done'

if [ $? -eq 0 ]; then
    echo "✓ API server is ready"
    echo ""
    kubectl get nodes
else
    echo "✗ API server failed to start"
    exit 1
fi

echo ""
echo "=== Creating test pod ==="
cat > /tmp/test-layer3.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-layer3
spec:
  containers:
  - name: pause
    image: rancher/mirrored-pause:3.6
    command: ["/pause"]
EOF

kubectl apply -f /tmp/test-layer3.yaml
echo "Pod created, waiting 25 seconds..."
sleep 25

echo ""
echo "=== Pod Status ==="
kubectl get pod test-layer3 -o wide

echo ""
echo "=== Pod Events (last 35 lines) ==="
kubectl describe pod test-layer3 | tail -35

echo ""
echo "=== Checking for previous blockers in logs ==="
echo "cap_last_cap errors: $(grep -c 'cap_last_cap' /tmp/k3s-layer3-test.log)"
echo "session keyring errors: $(grep -c 'session keyring' /tmp/k3s-layer3-test.log)"

echo ""
echo "=== Test complete ==="
