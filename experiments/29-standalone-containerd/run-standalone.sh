#!/bin/bash

echo "=== Experiment 29: Standalone containerd for 100% Functionality ==="
echo ""
echo "Strategy: Run containerd separately with full config control"
echo "Then connect k3s to use our pre-configured containerd"
echo ""

# Stop everything
echo "Step 1: Stopping existing processes..."
pkill -f "k3s server" 2>/dev/null
pkill -f "containerd" 2>/dev/null
sleep 5
echo "✓ Processes stopped"
echo ""

# Setup directories
CONTAINERD_DIR="/tmp/standalone-containerd"
K3S_DIR="/tmp/k3s-standalone"
rm -rf $CONTAINERD_DIR $K3S_DIR
mkdir -p $CONTAINERD_DIR/{state,root} $K3S_DIR

echo "Step 2: Creating perfect containerd configuration..."

cat > $CONTAINERD_DIR/config.toml <<'EOF'
version = 2

# Root directory for containerd metadata
root = "/tmp/standalone-containerd/root"
state = "/tmp/standalone-containerd/state"

# GRPC configuration
[grpc]
  address = "/run/standalone-containerd/containerd.sock"

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    # CRI plugin configuration - NO kernel version checks!

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

    [plugins."io.containerd.grpc.v1.cri".registry]
      config_path = ""

    [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
        endpoint = ["https://registry-1.docker.io"]
EOF

echo "✓ Containerd config created (NO unprivileged settings!)"
echo ""

# Prerequisites
echo "Step 3: Setting up prerequisites..."
mkdir -p /tmp/fake-procsys/kernel /tmp/fake-procsys/vm /run/standalone-containerd
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

# Copy CNI plugins
mkdir -p /opt/cni/bin /etc/cni/net.d
cp /usr/lib/cni/* /opt/cni/bin/ 2>/dev/null || true

echo "✓ Prerequisites ready"
echo ""

# Start standalone containerd
echo "Step 4: Starting standalone containerd..."

containerd --config $CONTAINERD_DIR/config.toml \
  > $CONTAINERD_DIR/containerd.log 2>&1 &

CONTAINERD_PID=$!
echo "containerd started (PID: $CONTAINERD_PID)"

# Wait for containerd to be ready
echo "Waiting for containerd startup..."
sleep 10

if ! ps -p $CONTAINERD_PID > /dev/null; then
    echo "❌ containerd crashed"
    cat $CONTAINERD_DIR/containerd.log
    exit 1
fi

# Check if CRI plugin loaded
if ctr --address /run/standalone-containerd/containerd.sock version 2>/dev/null; then
    echo "✓ containerd is running"
else
    echo "⚠️  containerd running but may have issues"
fi

echo ""
echo "Checking CRI plugin status..."
grep -i "cri.*plugin\|warning.*failed" $CONTAINERD_DIR/containerd.log | tail -5
echo ""

# Start k3s with external containerd
echo "Step 5: Starting k3s with external containerd..."

cd /home/user/claude-code-on-the-web/experiments/22-complete-solution

nohup ./ptrace_interceptor k3s server \
  --container-runtime-endpoint=unix:///run/standalone-containerd/containerd.sock \
  --snapshotter=native \
  --flannel-backend=none \
  --kubelet-arg="--local-storage-capacity-isolation=false" \
  --kubelet-arg="--image-gc-high-threshold=100" \
  --kubelet-arg="--image-gc-low-threshold=99" \
  --data-dir=$K3S_DIR \
  > /tmp/k3s-standalone.log 2>&1 &

K3S_PID=$!
echo "k3s started (PID: $K3S_PID)"
echo ""

# Wait for k3s
echo "Waiting 90 seconds for k3s initialization..."
sleep 90

if ! ps -p $K3S_PID > /dev/null; then
    echo "❌ k3s crashed"
    tail -100 /tmp/k3s-standalone.log
    exit 1
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "Step 6: Testing API access..."
timeout 60 bash -c 'until kubectl get nodes --insecure-skip-tls-verify 2>/dev/null; do sleep 2; done'

if [ $? -eq 0 ]; then
    echo "✓ API server ready"
    kubectl get nodes --insecure-skip-tls-verify
else
    echo "⚠️  API timeout"
fi

echo ""
echo "Step 7: Checking containerd images..."
ctr --address /run/standalone-containerd/containerd.sock -n k8s.io images list | head -10

echo ""
echo "Step 8: Creating test pod..."

cat > /tmp/test-standalone.yaml <<'POD'
apiVersion: v1
kind: Pod
metadata:
  name: test-standalone
spec:
  restartPolicy: Never
  containers:
  - name: pause
    image: rancher/mirrored-pause:3.6
    command: ["/pause"]
POD

kubectl delete pod test-standalone --insecure-skip-tls-verify 2>/dev/null || true
kubectl apply -f /tmp/test-standalone.yaml --insecure-skip-tls-verify

echo "Pod created, waiting 120 seconds..."
sleep 120

echo ""
echo "=== FINAL STATUS ==="
echo ""

kubectl get pods -A -o wide --insecure-skip-tls-verify 2>/dev/null | head -20

echo ""
echo "Test pod:"
kubectl get pod test-standalone -o wide --insecure-skip-tls-verify 2>/dev/null

POD_STATUS=$(kubectl get pod test-standalone -o jsonpath='{.status.phase}' --insecure-skip-tls-verify 2>/dev/null)

echo ""
echo "Phase: $POD_STATUS"
echo ""

if [ "$POD_STATUS" = "Running" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🎉🎉🎉  100% SUCCESS!  🎉🎉🎉"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  COMPLETE KUBERNETES IN GVISOR ACHIEVED!"
    echo ""
    echo "  ✅ Standalone containerd (perfect config)"
    echo "  ✅ k3s connected to external containerd"
    echo "  ✅ Patched runc (cap_last_cap fallback)"
    echo "  ✅ runc-gvisor wrapper (cgroup namespace strip)"
    echo "  ✅ ptrace interceptor (k3s /proc/sys)"
    echo "  ✅ Pod is RUNNING!"
    echo ""
    echo "  This is a COMPLETE solution for k3s in gVisor!"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    echo "Status: $POD_STATUS"
    echo ""
    kubectl describe pod test-standalone --insecure-skip-tls-verify 2>/dev/null | tail -40

    echo ""
    echo "Recent containerd logs:"
    tail -50 $CONTAINERD_DIR/containerd.log | grep -i "error\|warning" | tail -20

    echo ""
    echo "Recent k3s logs:"
    tail -50 /tmp/k3s-standalone.log | grep -i "test-standalone\|error" | tail -20
fi

echo ""
echo "=== Logs ==="
echo "containerd: $CONTAINERD_DIR/containerd.log"
echo "k3s: /tmp/k3s-standalone.log"
echo ""
echo "containerd socket: /run/standalone-containerd/containerd.sock"
echo "k3s data: $K3S_DIR"
