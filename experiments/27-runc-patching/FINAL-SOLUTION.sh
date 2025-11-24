#!/bin/bash

echo "=== FINAL COMPLETE SOLUTION FOR K3S IN GVISOR ==="
echo ""
echo "Components:"
echo "  1. Patched runc (cap_last_cap fallback)"
echo "  2. runc-gvisor wrapper (strips cgroup namespace)"
echo "  3. ptrace interceptor (k3s /proc/sys access)"
echo "  4. Pre-configured pause container"
echo ""

pkill -f "k3s server" && sleep 3

# Setup
mkdir -p /tmp/k3s-FINAL/agent/etc/containerd /tmp/k3s-FINAL/agent/images
mkdir -p /tmp/fake-procsys/kernel /tmp/fake-procsys/vm

# Fake /proc/sys files
echo "40" > /tmp/fake-procsys/kernel/cap_last_cap
echo "0" > /tmp/fake-procsys/kernel/panic
echo "0" > /tmp/fake-procsys/kernel/panic_on_oops
echo "999999" > /tmp/fake-procsys/kernel/keys/root_maxkeys  
echo "25000000" > /tmp/fake-procsys/kernel/keys/root_maxbytes
echo "1" > /tmp/fake-procsys/vm/overcommit_memory
echo "0" > /tmp/fake-procsys/vm/panic_on_oom
echo "4.4.0" > /tmp/fake-procsys/kernel/osrelease

touch /dev/kmsg && mount --bind /dev/null /dev/kmsg 2>/dev/null || true

# Save pause image for k3s airgap
podman save rancher/mirrored-pause:3.6 -o /tmp/k3s-FINAL/agent/images/pause.tar 2>/dev/null || \
  echo "Pause image save skipped (may already exist)"

# Contain configuration  
cat > /tmp/k3s-FINAL/agent/etc/containerd/config.toml.tmpl <<'EOF'
[plugins.'io.containerd.cri.v1.runtime']
  enable_unprivileged_ports = false

[plugins.'io.containerd.cri.v1.images']
  snapshotter = "native"

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc]
  runtime_type = "io.containerd.runc.v2"

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
  BinaryName = "/usr/bin/runc-gvisor"
  SystemdCgroup = false
  NoNewKeyring = true
EOF

echo "✓ Setup complete"
echo ""

# Start k3s
cd /home/user/claude-code-on-the-web/experiments/22-complete-solution

nohup ./ptrace_interceptor k3s server \
  --snapshotter=native \
  --flannel-backend=none \
  --kubelet-arg="--local-storage-capacity-isolation=false" \
  --kubelet-arg="--image-gc-high-threshold=100" \
  --kubelet-arg="--image-gc-low-threshold=99" \
  --data-dir=/tmp/k3s-FINAL \
  > /tmp/k3s-FINAL.log 2>&1 &

K3S_PID=$!
echo "k3s starting (PID: $K3S_PID)"
echo "Waiting 90 seconds for full initialization..."
sleep 90

if ! ps -p $K3S_PID > /dev/null; then
    echo "❌ k3s crashed"
    tail -100 /tmp/k3s-FINAL.log
    exit 1
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "✓ k3s running, testing API..."
timeout 30 bash -c 'until kubectl get nodes 2>/dev/null; do sleep 2; done'

if [ $? -ne 0 ]; then
    echo "⚠️  API timeout"
fi

kubectl get nodes 2>/dev/null || echo "Nodes not ready"
echo ""

# Create simplest possible test pod
cat > /tmp/test-FINAL.yaml <<'POD'
apiVersion: v1
kind: Pod
metadata:
  name: test-final
spec:
  restartPolicy: Never
  containers:
  - name: test
    image: rancher/mirrored-pause:3.6
    command: ["/pause"]
POD

kubectl delete pod test-final 2>/dev/null || true
kubectl apply -f /tmp/test-FINAL.yaml 2>/dev/null

echo "Pod created, waiting 90 seconds..."
sleep 90

echo ""
echo "=== FINAL STATUS ==="
kubectl get pod test-final -o wide 2>/dev/null
POD_STATUS=$(kubectl get pod test-final -o jsonpath='{.status.phase}' 2>/dev/null)

echo ""
echo "Phase: $POD_STATUS"
echo ""

if [ "$POD_STATUS" = "Running" ]; then
    echo "🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉"
    echo "🎉 100% SUCCESS!!! 🎉"
    echo "🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉"
    echo ""
    echo "COMPLETE K8S ACHIEVED IN GVISOR!"
else
    echo "Status: $POD_STATUS"
    echo ""
    kubectl describe pod test-final 2>/dev/null | tail -30
    echo ""
    echo "Recent containerd/runc errors:"
    tail -50 /tmp/k3s-FINAL.log | grep -i "test-final\|runc\|containerd" | tail -20
fi

echo ""
echo "Logs: /tmp/k3s-FINAL.log"
