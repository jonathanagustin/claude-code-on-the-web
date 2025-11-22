#!/bin/bash
#
# start-k3s-native.sh - Start k3s control-plane natively (no Docker)
#
# This script starts a fully functional k3s control plane in control-plane-only
# mode using the fake CNI plugin discovery method.
#
# Breakthrough: k3s --disable-agent still initializes agent components and
# requires CNI plugins to be discoverable. By providing a minimal fake CNI
# plugin, we allow initialization to complete and the API server to start.
#

set -e

# Configuration
K3S_DATA_DIR="${K3S_DATA_DIR:-/tmp/k3s-control-plane}"
KUBECONFIG_PATH="${KUBECONFIG:-$K3S_DATA_DIR/kubeconfig.yaml}"

echo "========================================================"
echo "k3s Native Control-Plane Setup"
echo "========================================================"
echo ""

# Step 1: Create fake CNI plugin
echo "[1/4] Setting up fake CNI plugin..."
mkdir -p /opt/cni/bin

if [ ! -f /opt/cni/bin/host-local ]; then
    cat > /opt/cni/bin/host-local << 'EOF'
#!/bin/bash
# Minimal fake CNI plugin for control-plane-only mode
# Returns valid JSON to satisfy k3s initialization checks
echo '{"cniVersion": "0.4.0", "ips": [{"version": "4", "address": "10.244.0.1/24"}]}'
exit 0
EOF
    chmod +x /opt/cni/bin/host-local
    echo "✓ Created fake CNI plugin at /opt/cni/bin/host-local"
else
    echo "✓ Fake CNI plugin already exists"
fi

# Step 2: Add CNI to PATH
echo ""
echo "[2/4] Configuring environment..."
export PATH=$PATH:/opt/cni/bin
echo "✓ Added /opt/cni/bin to PATH"

# Step 3: Prepare data directory
echo ""
echo "[3/4] Preparing k3s data directory..."
mkdir -p "$K3S_DATA_DIR/logs"
echo "✓ Data directory: $K3S_DATA_DIR"

# Step 4: Start k3s server
echo ""
echo "[4/4] Starting k3s server..."
echo "  Flags:"
echo "    --disable-agent (control-plane only)"
echo "    --disable=coredns,servicelb,traefik,local-storage,metrics-server"
echo ""

nohup k3s server \
  --disable-agent \
  --disable=coredns,servicelb,traefik,local-storage,metrics-server \
  --data-dir="$K3S_DATA_DIR/data" \
  > "$K3S_DATA_DIR/logs/server.log" 2>&1 &

K3S_PID=$!
echo "k3s server started with PID: $K3S_PID"

# Wait for API server to be ready
echo ""
echo "Waiting for API server to become ready..."
export KUBECONFIG="$K3S_DATA_DIR/data/server/cred/admin.kubeconfig"

READY=false
for i in {1..60}; do
    if kubectl get --raw /healthz &>/dev/null; then
        READY=true
        break
    fi
    echo -n "."
    sleep 1
done

echo ""
if [ "$READY" = true ]; then
    echo "✓ API server is ready!"
else
    echo "✗ API server failed to start within 60 seconds"
    echo "Check logs at: $K3S_DATA_DIR/logs/server.log"
    exit 1
fi

# Copy kubeconfig to convenient location
cp "$K3S_DATA_DIR/data/server/cred/admin.kubeconfig" "$KUBECONFIG_PATH"
echo "✓ Kubeconfig copied to: $KUBECONFIG_PATH"

# Verify functionality
echo ""
echo "Verifying k3s control plane..."
kubectl version --short 2>/dev/null || kubectl version | grep -E "(Client|Server) Version"
echo ""
kubectl get namespaces

# Summary
echo ""
echo "========================================================"
echo "✅ k3s Control Plane is READY!"
echo "========================================================"
echo ""
echo "📋 Configuration:"
echo "   KUBECONFIG=$KUBECONFIG_PATH"
echo "   Data Directory: $K3S_DATA_DIR"
echo "   Logs: $K3S_DATA_DIR/logs/server.log"
echo "   PID: $K3S_PID"
echo ""
echo "🚀 Usage:"
echo "   export KUBECONFIG=$KUBECONFIG_PATH"
echo "   kubectl get namespaces"
echo "   kubectl create namespace test"
echo "   kubectl create deployment nginx --image=nginx"
echo ""
echo "✅ What Works:"
echo "   - All kubectl commands"
echo "   - Helm chart development (helm template, helm lint)"
echo "   - Resource creation (Deployments, Services, ConfigMaps, etc.)"
echo "   - RBAC testing"
echo "   - Server-side dry-run (kubectl apply --dry-run=server)"
echo ""
echo "⚠️  What Doesn't Work:"
echo "   - Pod execution (no worker nodes)"
echo "   - Container logs/exec"
echo "   - Actual networking"
echo ""
echo "🛑 To stop k3s:"
echo "   killall k3s"
echo ""
echo "📖 Documentation: ./README.md"
echo "========================================================"

exit 0
