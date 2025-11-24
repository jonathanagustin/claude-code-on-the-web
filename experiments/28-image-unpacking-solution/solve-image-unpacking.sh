#!/bin/bash

echo "=== Experiment 28: Image Unpacking Solution ==="
echo ""
echo "Goal: Get pods to Running status by solving image unpacking"
echo ""

# Stop existing k3s
pkill -f "k3s server" 2>/dev/null
sleep 3

# Setup
DATA_DIR="/tmp/k3s-100"
rm -rf $DATA_DIR
mkdir -p $DATA_DIR/agent/{etc/containerd,images}

echo "Step 1: Preparing images for airgap mode..."

# Export pause image
if podman images | grep -q "mirrored-pause"; then
    echo "Exporting pause image..."
    podman save rancher/mirrored-pause:3.6 -o $DATA_DIR/agent/images/pause.tar
    echo "✓ Pause image exported"
else
    echo "⚠️  Pause image not found in podman"
fi

# Also try with k3s image itself
if podman images | grep -q "rancher/k3s"; then
    echo "Exporting k3s image for test pod..."
    podman save rancher/k3s:latest -o $DATA_DIR/agent/images/k3s.tar
    echo "✓ k3s image exported"
fi

echo ""
echo "Step 2: Configuring containerd..."

cat > $DATA_DIR/agent/etc/containerd/config.toml.tmpl <<'EOF'
# Containerd config for gVisor with image unpacking fix

[plugins.'io.containerd.cri.v1.runtime']
  # No unprivileged settings - they break in gVisor

[plugins.'io.containerd.cri.v1.images']
  snapshotter = "native"

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc]
  runtime_type = "io.containerd.runc.v2"

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
  BinaryName = "/usr/bin/runc-gvisor"
  SystemdCgroup = false
  NoNewKeyring = true
EOF

echo "✓ Containerd config created"
echo ""

# Prerequisites
echo "Step 3: Setting up prerequisites..."
mkdir -p /tmp/fake-procsys/kernel /tmp/fake-procsys/vm
echo "40" > /tmp/fake-procsys/kernel/cap_last_cap
echo "0" > /tmp/fake-procsys/kernel/panic
echo "0" > /tmp/fake-procsys/kernel/panic_on_oops
echo "999999" > /tmp/fake-procsys/kernel/keys/root_maxkeys
echo "25000000" > /tmp/fake-procsys/kernel/keys/root_maxbytes
echo "1" > /tmp/fake-procsys/vm/overcommit_memory
echo "0" > /tmp/fake-procsys/vm/panic_on_oom
echo "4.4.0" > /tmp/fake-procsys/kernel/osrelease

touch /dev/kmsg
mount --bind /dev/null /dev/kmsg 2>/dev/null || true

echo "✓ Prerequisites ready"
echo ""

# Start k3s
echo "Step 4: Starting k3s with complete solution..."
cd /home/user/claude-code-on-the-web/experiments/22-complete-solution

nohup ./ptrace_interceptor k3s server \
  --snapshotter=native \
  --flannel-backend=none \
  --kubelet-arg="--local-storage-capacity-isolation=false" \
  --kubelet-arg="--image-gc-high-threshold=100" \
  --kubelet-arg="--image-gc-low-threshold=99" \
  --data-dir=$DATA_DIR \
  > /tmp/k3s-100.log 2>&1 &

K3S_PID=$!
echo "k3s started (PID: $K3S_PID)"
echo ""

# Wait for startup
echo "Waiting 60 seconds for k3s initialization..."
sleep 60

if ! ps -p $K3S_PID > /dev/null; then
    echo "❌ k3s crashed"
    tail -100 /tmp/k3s-100.log
    exit 1
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "Step 5: Waiting for API server..."
timeout 60 bash -c 'until kubectl get nodes 2>/dev/null; do sleep 2; done'

if [ $? -eq 0 ]; then
    echo "✓ API server ready"
    kubectl get nodes
else
    echo "⚠️  API timeout, but continuing..."
fi

echo ""
echo "Step 6: Checking if images were loaded..."

# Wait a bit more for image import
sleep 20

# Check containerd images
echo "Images in containerd:"
ctr -n k8s.io images list 2>/dev/null | grep -E "pause|k3s" || echo "No images found yet"

echo ""
echo "Step 7: Creating test pod..."

# Create pod that uses pre-loaded image
cat > /tmp/test-100.yaml <<'POD'
apiVersion: v1
kind: Pod
metadata:
  name: test-100
spec:
  restartPolicy: Never
  containers:
  - name: test
    image: rancher/mirrored-pause:3.6
    imagePullPolicy: Never
    command: ["/pause"]
POD

kubectl delete pod test-100 2>/dev/null || true
kubectl apply -f /tmp/test-100.yaml

echo "Pod created, waiting 90 seconds..."
sleep 90

echo ""
echo "=== FINAL STATUS ==="
echo ""

kubectl get pods -A -o wide 2>/dev/null | head -20

echo ""
echo "Test pod status:"
kubectl get pod test-100 -o wide 2>/dev/null

POD_STATUS=$(kubectl get pod test-100 -o jsonpath='{.status.phase}' 2>/dev/null)

echo ""
echo "Phase: $POD_STATUS"
echo ""

if [ "$POD_STATUS" = "Running" ]; then
    echo "🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉"
    echo "🎉                                              🎉"
    echo "🎉  100% SUCCESS! POD IS RUNNING!              🎉"
    echo "🎉                                              🎉"
    echo "🎉  COMPLETE KUBERNETES IN GVISOR ACHIEVED!    🎉"
    echo "🎉                                              🎉"
    echo "🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉"
    echo ""
    echo "All components working:"
    echo "  ✅ Patched runc (cap_last_cap)"
    echo "  ✅ runc-gvisor wrapper (cgroup namespace)"
    echo "  ✅ Containerd CRI plugin (fixed config)"
    echo "  ✅ Image loading (airgap mode)"
    echo "  ✅ Pod execution (RUNNING!)"
    echo ""
    echo "This is a complete k3s solution for gVisor!"
else
    echo "Status: $POD_STATUS"
    echo ""
    echo "Pod events:"
    kubectl describe pod test-100 2>/dev/null | tail -30

    echo ""
    echo "Recent errors in k3s logs:"
    tail -100 /tmp/k3s-100.log | grep -i "test-100\|error.*image\|error.*pull" | tail -20

    echo ""
    echo "Containerd status:"
    ctr -n k8s.io containers list 2>/dev/null | head -10
fi

echo ""
echo "=== Logs ==="
echo "k3s: /tmp/k3s-100.log"
echo "containerd: $DATA_DIR/agent/containerd/containerd.log"
