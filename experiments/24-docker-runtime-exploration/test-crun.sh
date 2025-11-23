#!/bin/bash

# Test crun as alternative runtime

echo "=== Testing crun Runtime ==="
echo "crun is already configured in containerd config"
echo ""

# Create a simple pod manifest that uses crun runtime
cat > /tmp/test-crun-pod.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-crun
  annotations:
    io.kubernetes.cri.runtime: crun
spec:
  runtimeClassName: crun
  containers:
  - name: pause
    image: rancher/mirrored-pause:3.6
    command: ["/pause"]
EOF

echo "Created pod manifest using crun runtime"
cat /tmp/test-crun-pod.yaml
echo ""

# Wait for k3s to be ready
echo "Waiting for k3s API server..."
timeout 60 bash -c 'until kubectl get nodes 2>/dev/null; do sleep 2; done'

# Try to create the pod
echo ""
echo "Attempting to create pod with crun runtime..."
kubectl apply -f /tmp/test-crun-pod.yaml

# Wait a bit
sleep 10

# Check pod status
echo ""
echo "=== Pod Status ==="
kubectl get pod test-crun -o wide
echo ""
kubectl describe pod test-crun | tail -30

# Check logs
echo ""
echo "=== Recent k3s logs ==="
tail -50 /tmp/k3s-complete.log | grep -i crun || echo "No crun-specific logs"
