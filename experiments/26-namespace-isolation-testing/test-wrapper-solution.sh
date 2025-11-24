#!/bin/bash

echo "=== Experiment 26: Testing runc Wrapper Solution ==="
echo ""
echo "Goal: Strip cgroup namespace from OCI specs to enable pod execution"
echo ""

# Step 1: Install the wrapper
echo "Step 1: Installing runc-gvisor wrapper..."

if [ ! -f /usr/bin/runc.real ]; then
    echo "Backing up original runc..."
    cp /usr/bin/runc /usr/bin/runc.real
fi

echo "Installing wrapper..."
cp experiments/26-namespace-isolation-testing/runc-gvisor-wrapper.sh /usr/bin/runc-gvisor
chmod +x /usr/bin/runc-gvisor

echo "✓ Wrapper installed at /usr/bin/runc-gvisor"
echo ""

# Step 2: Test wrapper with manual runc test
echo "Step 2: Testing wrapper with manual container..."

TEST_DIR="/tmp/wrapper-test"
rm -rf $TEST_DIR
mkdir -p $TEST_DIR/rootfs/{bin,lib/x86_64-linux-gnu,lib64}

# Create rootfs
cp /bin/sh $TEST_DIR/rootfs/bin/
cp /bin/echo $TEST_DIR/rootfs/bin/
cp /lib/x86_64-linux-gnu/libc.so.6 $TEST_DIR/rootfs/lib/x86_64-linux-gnu/
cp /lib64/ld-linux-x86-64.so.2 $TEST_DIR/rootfs/lib64/

cd $TEST_DIR

# Create config WITH cgroup namespace (to test stripping)
cat > config.json <<'EOF'
{
  "ociVersion": "1.0.0",
  "process": {
    "terminal": false,
    "user": {"uid": 0, "gid": 0},
    "args": ["/bin/sh", "-c", "echo 'SUCCESS: Wrapper stripped cgroup namespace!'"],
    "env": ["PATH=/bin"],
    "cwd": "/"
  },
  "root": {"path": "rootfs", "readonly": false},
  "mounts": [
    {"destination": "/proc", "type": "proc", "source": "proc"},
    {"destination": "/dev", "type": "tmpfs", "source": "tmpfs"}
  ],
  "linux": {
    "namespaces": [
      {"type": "pid"},
      {"type": "ipc"},
      {"type": "uts"},
      {"type": "mount"},
      {"type": "cgroup"}
    ]
  }
}
EOF

echo "Config created WITH cgroup namespace"
echo "Testing with wrapper..."

/usr/bin/runc-gvisor run wrapper-test 2>&1 | tee /tmp/wrapper-test.log
WRAPPER_STATUS=$?

runc delete wrapper-test 2>/dev/null || true

if [ $WRAPPER_STATUS -eq 0 ] && grep -q "SUCCESS" /tmp/wrapper-test.log; then
    echo "✅ Wrapper test PASSED"
    echo "   The wrapper successfully stripped cgroup namespace!"
    echo ""
else
    echo "❌ Wrapper test FAILED"
    cat /tmp/wrapper-test.log
    echo ""
    echo "Wrapper may need debugging. Check /tmp/wrapper-test.log"
    exit 1
fi

# Step 3: Update containerd config
echo "Step 3: Updating containerd configuration..."

cat > /tmp/k3s-complete/agent/etc/containerd/config.toml.tmpl <<'EOF'
# Containerd configuration for gVisor compatibility
# Uses runc-gvisor wrapper to strip unsupported cgroup namespace

[plugins.'io.containerd.cri.v1.runtime']
  enable_unprivileged_ports = false
  enable_unprivileged_icmp = false

[plugins.'io.containerd.cri.v1.images']
  snapshotter = "native"

[plugins.'io.containerd.cri.v1.images'.pinned_images]
  sandbox = "rancher/mirrored-pause:3.6"

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc]
  runtime_type = "io.containerd.runc.v2"

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
  BinaryName = "/usr/bin/runc-gvisor"
  SystemdCgroup = false
  NoNewKeyring = true
EOF

echo "✓ Containerd config updated to use runc-gvisor wrapper"
echo ""

# Step 4: Start k3s with wrapper
echo "Step 4: Starting k3s with wrapper solution..."

# Stop any existing k3s
pkill -f "k3s server" 2>/dev/null
sleep 3

# Ensure prerequisites
mkdir -p /tmp/fake-procsys/kernel
echo "40" > /tmp/fake-procsys/kernel/cap_last_cap
touch /dev/kmsg
mount --bind /dev/null /dev/kmsg 2>/dev/null || true
unshare --mount --propagation unchanged bash -c 'mount --make-rshared /' 2>/dev/null || true

echo "Starting k3s..."
cd /home/user/claude-code-on-the-web/experiments/22-complete-solution

nohup ./ptrace_interceptor k3s server \
  --snapshotter=native \
  --flannel-backend=none \
  --kubelet-arg="--local-storage-capacity-isolation=false" \
  --kubelet-arg="--image-gc-high-threshold=100" \
  --kubelet-arg="--image-gc-low-threshold=99" \
  --data-dir=/tmp/k3s-complete \
  > /tmp/k3s-wrapper-test.log 2>&1 &

K3S_PID=$!
echo "k3s started (PID: $K3S_PID)"
echo "Waiting 30 seconds for startup..."
sleep 30

if ! ps -p $K3S_PID > /dev/null; then
    echo "❌ k3s crashed"
    tail -50 /tmp/k3s-wrapper-test.log
    exit 1
fi

echo "✓ k3s is running"
echo ""

# Step 5: Wait for API and create test pod
echo "Step 5: Testing pod creation..."

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
timeout 60 bash -c 'until kubectl get nodes 2>/dev/null; do sleep 2; done'

if [ $? -ne 0 ]; then
    echo "❌ API server not ready"
    exit 1
fi

echo "✓ API server ready"
kubectl get nodes
echo ""

# Create test pod
cat > /tmp/test-wrapper-pod.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-wrapper
spec:
  containers:
  - name: test
    image: rancher/mirrored-pause:3.6
    command: ["/pause"]
EOF

kubectl delete pod test-wrapper 2>/dev/null || true
kubectl apply -f /tmp/test-wrapper-pod.yaml

echo "Pod created, waiting 30 seconds..."
sleep 30

echo ""
echo "=== Pod Status ==="
kubectl get pod test-wrapper -o wide

echo ""
echo "=== Pod Events ==="
kubectl describe pod test-wrapper | tail -40

echo ""
echo "=== Analysis ==="

POD_STATUS=$(kubectl get pod test-wrapper -o jsonpath='{.status.phase}' 2>/dev/null)

if [ "$POD_STATUS" = "Running" ]; then
    echo "🎉 SUCCESS! Pod is RUNNING!"
    echo ""
    echo "   The runc-gvisor wrapper successfully enabled pod execution!"
    echo "   Cgroup namespace was stripped, allowing containers to start!"
    echo ""
    echo "   This is a complete solution for k3s in gVisor!"
elif grep -q "cap_last_cap" <(kubectl describe pod test-wrapper 2>&1); then
    echo "⚠️  Still blocked by cap_last_cap"
    echo "   Wrapper works but LD_PRELOAD not propagating"
    echo "   Need to ensure LD_PRELOAD is set in wrapper"
elif grep -q "cgroup" <(kubectl describe pod test-wrapper 2>&1); then
    echo "⚠️  Still blocked by cgroup issues"
    echo "   Wrapper may not be stripping namespace correctly"
    echo "   Check wrapper logic"
else
    echo "⚠️  Pod status: $POD_STATUS"
    echo "   Check events above for details"
fi

echo ""
echo "=== Test Complete ==="
echo "k3s logs: /tmp/k3s-wrapper-test.log"
echo "Wrapper test log: /tmp/wrapper-test.log"
