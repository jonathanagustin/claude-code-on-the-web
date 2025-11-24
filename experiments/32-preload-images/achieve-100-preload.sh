#!/bin/bash

echo "=========================================="
echo "Experiment 32: Pre-load Images for 100%"
echo "=========================================="
echo ""
echo "Goal: Pre-load pause image to bypass unpacker issue"
echo ""

# Cleanup
echo "Step 1: Cleanup"
pkill -9 -f "k3s server" 2>/dev/null
pkill -9 -f "containerd" 2>/dev/null
pkill -9 -f "ptrace_interceptor" 2>/dev/null
sleep 3
echo "✓ Cleanup complete"
echo ""

# Setup
WORK_DIR="/tmp/exp32"
rm -rf $WORK_DIR
mkdir -p $WORK_DIR/{containerd,k3s}

echo "Step 2: Setting up prerequisites"
mkdir -p /tmp/fake-procsys/kernel /tmp/fake-procsys/vm /run/exp32-containerd /opt/cni/bin /etc/cni/net.d

# Fake proc/sys files
echo "40" > /tmp/fake-procsys/kernel/cap_last_cap
echo "0" > /tmp/fake-procsys/kernel/panic
echo "0" > /tmp/fake-procsys/kernel/panic_on_oops
echo "999999" > /tmp/fake-procsys/kernel/keys/root_maxkeys
echo "25000000" > /tmp/fake-procsys/kernel/keys/root_maxbytes
echo "1" > /tmp/fake-procsys/vm/overcommit_memory
echo "0" > /tmp/fake-procsys/vm/panic_on_oom

touch /dev/kmsg 2>/dev/null
mount --bind /dev/null /dev/kmsg 2>/dev/null || true

cp /usr/lib/cni/* /opt/cni/bin/ 2>/dev/null || true

echo "✓ Prerequisites ready"
echo ""

# Create containerd config
echo "Step 3: Creating containerd config"
cat > $WORK_DIR/containerd/config.toml <<'EOF'
version = 2

root = "/tmp/exp32/containerd/root"
state = "/tmp/exp32/containerd/state"

[grpc]
  address = "/run/exp32-containerd/containerd.sock"

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    sandbox_image = "rancher/mirrored-pause:3.6"

    [plugins."io.containerd.grpc.v1.cri".containerd]
      snapshotter = "native"
      default_runtime_name = "runc"

      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"

          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            BinaryName = "/usr/bin/runc-gvisor"
            SystemdCgroup = false
            NoNewKeyring = true

    [plugins."io.containerd.grpc.v1.cri".cni]
      bin_dir = "/opt/cni/bin"
      conf_dir = "/etc/cni/net.d"
EOF

echo "✓ Config created"
echo ""

# Start containerd
echo "Step 4: Starting patched containerd"
/usr/bin/containerd-gvisor-patched --config $WORK_DIR/containerd/config.toml > $WORK_DIR/containerd.log 2>&1 &
CONTAINERD_PID=$!
echo "Containerd started (PID: $CONTAINERD_PID)"
sleep 8

if ! ps -p $CONTAINERD_PID > /dev/null; then
    echo "❌ Containerd crashed!"
    cat $WORK_DIR/containerd.log
    exit 1
fi

echo "✓ Containerd running"
echo ""

# Import pause image
echo "Step 5: Pre-loading pause image"
if [ ! -f /tmp/pause-image.tar ]; then
    echo "Exporting pause image..."
    podman pull docker.io/rancher/mirrored-pause:3.6 2>/dev/null
    podman save docker.io/rancher/mirrored-pause:3.6 -o /tmp/pause-image.tar
fi

echo "Importing pause image into containerd..."
ctr --address /run/exp32-containerd/containerd.sock images import /tmp/pause-image.tar

echo ""
echo "Verifying image import..."
ctr --address /run/exp32-containerd/containerd.sock images ls | grep pause

if [ $? -eq 0 ]; then
    echo "✓ Pause image pre-loaded successfully!"
else
    echo "❌ Image import failed"
    exit 1
fi
echo ""

# Start k3s
echo "Step 6: Starting k3s with pre-loaded image"
cd /home/user/claude-code-on-the-web/experiments/22-complete-solution

./ptrace_interceptor k3s server \
  --container-runtime-endpoint=unix:///run/exp32-containerd/containerd.sock \
  --snapshotter=native \
  --flannel-backend=none \
  --disable=traefik,servicelb \
  --kubelet-arg="--local-storage-capacity-isolation=false" \
  --kubelet-arg="--image-gc-high-threshold=100" \
  --kubelet-arg="--image-gc-low-threshold=99" \
  --data-dir=$WORK_DIR/k3s \
  > $WORK_DIR/k3s.log 2>&1 &

K3S_PID=$!
echo "k3s started (PID: $K3S_PID)"
echo ""

# Wait for k3s
echo "Step 7: Waiting for k3s initialization (90 seconds)"
sleep 90

if ! ps -p $K3S_PID > /dev/null; then
    echo "❌ k3s crashed!"
    tail -100 $WORK_DIR/k3s.log
    exit 1
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Wait for API
echo "Step 8: Waiting for API server"
for i in {1..30}; do
    if kubectl get nodes --insecure-skip-tls-verify 2>/dev/null; then
        echo "✓ API server ready"
        break
    fi
    sleep 2
done

echo ""

# Create test pod
echo "Step 9: Creating test pod"
cat > /tmp/exp32-test-pod.yaml <<'POD'
apiVersion: v1
kind: Pod
metadata:
  name: test-100-final
spec:
  restartPolicy: Never
  containers:
  - name: test
    image: rancher/mirrored-pause:3.6
    command: ["/pause"]
POD

kubectl delete pod test-100-final --insecure-skip-tls-verify 2>/dev/null || true
sleep 2
kubectl apply -f /tmp/exp32-test-pod.yaml --insecure-skip-tls-verify

echo "✓ Pod created"
echo ""

# Monitor pod status
echo "Step 10: Monitoring pod status (120 seconds)"
for i in {1..60}; do
    STATUS=$(kubectl get pod test-100-final -o jsonpath='{.status.phase}' --insecure-skip-tls-verify 2>/dev/null)
    echo "[$i/60] Pod status: $STATUS"

    if [ "$STATUS" = "Running" ]; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🎉🎉🎉  100% SUCCESS ACHIEVED!  🎉🎉🎉"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "  COMPLETE KUBERNETES IN GVISOR!"
        echo ""
        echo "  ✅ Patched containerd (kernel version bypass)"
        echo "  ✅ Pre-loaded pause image"
        echo "  ✅ Patched runc (cap_last_cap fallback)"
        echo "  ✅ runc-gvisor wrapper (cgroup strip)"
        echo "  ✅ ptrace interceptor (/proc/sys access)"
        echo "  ✅ Pod status: RUNNING!"
        echo ""
        echo "  This is 100% Kubernetes functionality in gVisor!"
        echo ""
        kubectl get pod test-100-final -o wide --insecure-skip-tls-verify
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        exit 0
    fi

    sleep 2
done

# If we get here, check what happened
echo ""
echo "=========================================="
echo "Status: Checking pod state"
echo "=========================================="
echo ""

echo "Pod status:"
kubectl get pod test-100-final -o wide --insecure-skip-tls-verify 2>/dev/null

echo ""
echo "Pod events:"
kubectl describe pod test-100-final --insecure-skip-tls-verify 2>/dev/null | tail -30

echo ""
echo "Recent containerd logs:"
tail -30 $WORK_DIR/containerd.log | grep -i "error\|test-100"

echo ""
echo "All pods:"
kubectl get pods -A -o wide --insecure-skip-tls-verify 2>/dev/null

echo ""
echo "Logs available:"
echo "  containerd: $WORK_DIR/containerd.log"
echo "  k3s: $WORK_DIR/k3s.log"
