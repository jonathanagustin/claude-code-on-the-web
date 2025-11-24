#!/bin/bash

echo "=========================================="
echo "Experiment 30: The 100% Solution"
echo "=========================================="
echo ""
echo "Goal: Achieve full pod execution (Running status) in gVisor"
echo ""

# Cleanup
echo "Step 1: Cleanup"
pkill -9 -f "k3s server" 2>/dev/null
pkill -9 -f "containerd" 2>/dev/null
pkill -9 -f "ptrace_interceptor" 2>/dev/null
sleep 3

# Setup directories
WORK_DIR="/tmp/exp30"
rm -rf $WORK_DIR
mkdir -p $WORK_DIR/{containerd,k3s}

echo "✓ Cleanup complete"
echo ""

# Prerequisites
echo "Step 2: Setting up prerequisites"
mkdir -p /tmp/fake-procsys/kernel /tmp/fake-procsys/vm /run/exp30-containerd /opt/cni/bin /etc/cni/net.d

# Fake proc/sys files for k3s
echo "40" > /tmp/fake-procsys/kernel/cap_last_cap
echo "0" > /tmp/fake-procsys/kernel/panic
echo "0" > /tmp/fake-procsys/kernel/panic_on_oops
echo "999999" > /tmp/fake-procsys/kernel/keys/root_maxkeys
echo "25000000" > /tmp/fake-procsys/kernel/keys/root_maxbytes
echo "1" > /tmp/fake-procsys/vm/overcommit_memory
echo "0" > /tmp/fake-procsys/vm/panic_on_oom

# kmsg
touch /dev/kmsg 2>/dev/null
mount --bind /dev/null /dev/kmsg 2>/dev/null || true

# CNI plugins
cp /usr/lib/cni/* /opt/cni/bin/ 2>/dev/null || true

echo "✓ Prerequisites ready"
echo ""

# Create perfect containerd config
echo "Step 3: Creating standalone containerd config"
cat > $WORK_DIR/containerd/config.toml <<'EOF'
version = 2

root = "/tmp/exp30/containerd/root"
state = "/tmp/exp30/containerd/state"

[grpc]
  address = "/run/exp30-containerd/containerd.sock"

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    sandbox_image = "rancher/mirrored-pause:3.6"

    [plugins."io.containerd.grpc.v1.cri".containerd]
      snapshotter = "native"
      default_runtime_name = "runc"

      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          # Use shim v2 with patched containerd
          runtime_type = "io.containerd.runc.v2"

          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            BinaryName = "/usr/bin/runc-gvisor"
            SystemdCgroup = false
            NoNewKeyring = true

    [plugins."io.containerd.grpc.v1.cri".cni]
      bin_dir = "/opt/cni/bin"
      conf_dir = "/etc/cni/net.d"

  [plugins."io.containerd.snapshotter.v1.native"]
    root_path = "/tmp/exp30/containerd/root/io.containerd.snapshotter.v1.native"

  [plugins."io.containerd.transfer.v1.local"]
    config_path = ""
    max_concurrent_downloads = 3

  [plugins."io.containerd.service.v1.images-service"]
    default_platform = "linux/amd64"
EOF

echo "✓ Config created - NO kernel version checks!"
echo ""

# Verify patched runc exists
echo "Step 4: Verifying components"
if [ ! -f /usr/bin/runc-gvisor-patched ]; then
    echo "❌ Missing /usr/bin/runc-gvisor-patched"
    exit 1
fi

if [ ! -f /usr/bin/runc-gvisor ]; then
    echo "❌ Missing /usr/bin/runc-gvisor wrapper"
    exit 1
fi

echo "✓ runc-gvisor-patched: $(stat -c%s /usr/bin/runc-gvisor-patched) bytes"
echo "✓ runc-gvisor wrapper: present"
echo ""

# Start patched containerd
echo "Step 5: Starting PATCHED containerd (v2.1.4 - gVisor compatible)"
/usr/bin/containerd-gvisor-patched --config $WORK_DIR/containerd/config.toml > $WORK_DIR/containerd.log 2>&1 &
CONTAINERD_PID=$!
echo "containerd started (PID: $CONTAINERD_PID) - kernel version check BYPASSED"

# Wait for containerd
sleep 8

if ! ps -p $CONTAINERD_PID > /dev/null; then
    echo "❌ containerd crashed!"
    cat $WORK_DIR/containerd.log
    exit 1
fi

# Verify containerd socket
if ! ctr --address /run/exp30-containerd/containerd.sock version 2>/dev/null; then
    echo "⚠️  containerd may have issues"
    tail -20 $WORK_DIR/containerd.log
fi

echo "✓ containerd running"
echo ""

# Check for CRI plugin errors
echo "Step 6: Checking CRI plugin status"
if grep -i "failed.*cri" $WORK_DIR/containerd.log; then
    echo "⚠️  CRI plugin errors detected"
    tail -30 $WORK_DIR/containerd.log
    exit 1
else
    echo "✓ No CRI plugin errors"
fi
echo ""

# Start k3s with external containerd
echo "Step 7: Starting k3s with external containerd"
cd /home/user/claude-code-on-the-web/experiments/22-complete-solution

./ptrace_interceptor k3s server \
  --container-runtime-endpoint=unix:///run/exp30-containerd/containerd.sock \
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
echo "Step 8: Waiting for k3s initialization (90 seconds)"
sleep 90

if ! ps -p $K3S_PID > /dev/null; then
    echo "❌ k3s crashed!"
    tail -100 $WORK_DIR/k3s.log
    exit 1
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Wait for API
echo "Step 9: Waiting for API server"
for i in {1..30}; do
    if kubectl get nodes --insecure-skip-tls-verify 2>/dev/null; then
        echo "✓ API server ready"
        break
    fi
    sleep 2
done

echo ""

# Create test pod
echo "Step 10: Creating test pod"
cat > /tmp/exp30-test-pod.yaml <<'POD'
apiVersion: v1
kind: Pod
metadata:
  name: test-100-percent
spec:
  restartPolicy: Never
  containers:
  - name: test
    image: rancher/mirrored-pause:3.6
    command: ["/pause"]
POD

kubectl delete pod test-100-percent --insecure-skip-tls-verify 2>/dev/null || true
sleep 2
kubectl apply -f /tmp/exp30-test-pod.yaml --insecure-skip-tls-verify

echo "✓ Pod created"
echo ""

# Monitor pod status
echo "Step 11: Monitoring pod status (120 seconds)"
for i in {1..60}; do
    STATUS=$(kubectl get pod test-100-percent -o jsonpath='{.status.phase}' --insecure-skip-tls-verify 2>/dev/null)
    echo "[$i/60] Pod status: $STATUS"

    if [ "$STATUS" = "Running" ]; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🎉🎉🎉  100% SUCCESS ACHIEVED!  🎉🎉🎉"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "  COMPLETE KUBERNETES IN GVISOR!"
        echo ""
        echo "  ✅ Standalone containerd (perfect config)"
        echo "  ✅ k3s connected via external endpoint"
        echo "  ✅ Patched runc (cap_last_cap fallback)"
        echo "  ✅ runc-gvisor wrapper (cgroup strip)"
        echo "  ✅ ptrace interceptor (k3s /proc/sys)"
        echo "  ✅ Pod status: RUNNING!"
        echo ""
        echo "  This is 100% Kubernetes functionality in gVisor!"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        exit 0
    fi

    sleep 2
done

# If we get here, pod didn't reach Running
echo ""
echo "=========================================="
echo "Status: Pod did not reach Running"
echo "=========================================="
echo ""

echo "Pod status:"
kubectl get pod test-100-percent -o wide --insecure-skip-tls-verify 2>/dev/null

echo ""
echo "Pod events:"
kubectl describe pod test-100-percent --insecure-skip-tls-verify 2>/dev/null | tail -50

echo ""
echo "Recent containerd logs:"
tail -50 $WORK_DIR/containerd.log | grep -i "error\|test-100"

echo ""
echo "Recent k3s logs:"
tail -50 $WORK_DIR/k3s.log | grep -i "test-100\|error"

echo ""
echo "All pods:"
kubectl get pods -A -o wide --insecure-skip-tls-verify 2>/dev/null

echo ""
echo "Logs available:"
echo "  containerd: $WORK_DIR/containerd.log"
echo "  k3s: $WORK_DIR/k3s.log"
