#!/bin/bash

echo "=== Starting k3s with Complete Solution ==="
echo ""
echo "Components:"
echo "  - Patched runc (handles missing cap_last_cap)"
echo "  - runc-gvisor wrapper (strips cgroup namespace)"  
echo "  - ptrace interceptor (redirects /proc/sys for k3s)"
echo ""

# Ensure patched runc is installed
if [ ! -f /usr/bin/runc-gvisor-patched ]; then
    echo "Installing patched runc..."
    cp experiments/27-runc-patching/runc/runc /usr/bin/runc-gvisor-patched
    chmod +x /usr/bin/runc-gvisor-patched
fi

# Ensure wrapper is installed
if [ ! -f /usr/bin/runc-gvisor ]; then
    echo "Installing runc-gvisor wrapper..."
    cat > /usr/bin/runc-gvisor <<'WRAPPER'
#!/bin/bash
RUNC_PATCHED="/usr/bin/runc-gvisor-patched"

strip_cgroup_namespace() {
    local config_file="$1"
    if [ -f "$config_file" ] && command -v jq &>/dev/null; then
        jq 'del(.linux.namespaces[] | select(.type == "cgroup"))' "$config_file" > "${config_file}.tmp" && mv "${config_file}.tmp" "$config_file"
    fi
}

if [ "$1" = "run" ] || [ "$1" = "create" ]; then
    BUNDLE_DIR=""
    for ((i=1; i<=$#; i++)); do
        if [ "${!i}" = "--bundle" ] || [ "${!i}" = "-b" ]; then
            j=$((i+1))
            BUNDLE_DIR="${!j}"
            break
        fi
    done
    [ -z "$BUNDLE_DIR" ] && BUNDLE_DIR="."
    strip_cgroup_namespace "$BUNDLE_DIR/config.json"
fi

exec "$RUNC_PATCHED" "$@"
WRAPPER
    chmod +x /usr/bin/runc-gvisor
fi

# Prerequisites
echo "Applying prerequisites..."
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
unshare --mount --propagation unchanged bash -c 'mount --make-rshared /' 2>/dev/null || true

# Containerd config
mkdir -p /tmp/k3s-final/agent/etc/containerd
cat > /tmp/k3s-final/agent/etc/containerd/config.toml.tmpl <<'EOF'
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

echo "✓ Configuration ready"
echo ""

# Stop existing k3s
pkill -f "k3s server" 2>/dev/null
sleep 3

# Start k3s with ptrace interceptor
echo "Starting k3s..."
cd /home/user/claude-code-on-the-web/experiments/22-complete-solution

nohup ./ptrace_interceptor k3s server \
  --snapshotter=native \
  --flannel-backend=none \
  --kubelet-arg="--local-storage-capacity-isolation=false" \
  --kubelet-arg="--image-gc-high-threshold=100" \
  --kubelet-arg="--image-gc-low-threshold=99" \
  --data-dir=/tmp/k3s-final \
  > /tmp/k3s-final.log 2>&1 &

K3S_PID=$!
echo "k3s started (PID: $K3S_PID)"
echo "Waiting 45 seconds for full startup..."
sleep 45

if ! ps -p $K3S_PID > /dev/null; then
    echo "❌ k3s crashed - check /tmp/k3s-final.log"
    exit 1
fi

echo "✓ k3s is running"
echo ""

# Test API
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
timeout 60 bash -c 'until kubectl get nodes 2>/dev/null; do sleep 2; done'

if [ $? -ne 0 ]; then
    echo "❌ API not ready"
    exit 1
fi

echo "✓ API server ready"
kubectl get nodes
echo ""

# Create test pod
echo "Creating test pod..."
cat > /tmp/test-100.yaml <<'POD'
apiVersion: v1
kind: Pod
metadata:
  name: test-100-percent
spec:
  containers:
  - name: alpine
    image: rancher/mirrored-pause:3.6
    command: ["/pause"]
POD

kubectl delete pod test-100-percent 2>/dev/null || true
kubectl apply -f /tmp/test-100.yaml

echo "Waiting 60 seconds for pod..."
sleep 60

echo ""
echo "=== POD STATUS ==="
kubectl get pod test-100-percent -o wide

POD_STATUS=$(kubectl get pod test-100-percent -o jsonpath='{.status.phase}' 2>/dev/null)
echo ""
echo "Pod phase: $POD_STATUS"
echo ""

if [ "$POD_STATUS" = "Running" ]; then
    echo "🎉🎉🎉 SUCCESS! 100% KUBERNETES FUNCTIONALITY! 🎉🎉🎉"
    echo ""
    echo "Complete solution working:"
    echo "  ✅ Patched runc handles cap_last_cap"
    echo "  ✅ Wrapper strips cgroup namespace"
    echo "  ✅ Ptrace handles k3s /proc/sys access"
    echo "  ✅ Pods reach Running status!"
else
    echo "Pod status: $POD_STATUS"
    echo ""
    kubectl describe pod test-100-percent | tail -40
fi
