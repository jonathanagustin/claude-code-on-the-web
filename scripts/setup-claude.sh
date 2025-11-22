#!/bin/bash
#
# Automated setup script for Claude Code on the Web
# Installs Docker, k3s, kubectl, and other necessary tools
#

set -e

echo "====================================================================="
echo "Claude Code Environment Setup"
echo "====================================================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)"
    exit 1
fi

# Check if running in Claude Code web environment
if [ "$CLAUDE_CODE_REMOTE" != "true" ]; then
    echo "⚠️  Not running in Claude Code web environment, skipping setup"
    exit 0
fi

echo "✓ Running in Claude Code web environment"
echo ""

# ===================================================================
# 1. Install Docker
# ===================================================================
echo "Step 1/5: Installing Docker..."

if command -v docker &> /dev/null; then
    echo "  ✓ Docker already installed"
else
    echo "  Installing docker.io package..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq > /dev/null 2>&1
    apt-get install -y docker.io > /dev/null 2>&1
    echo "  ✓ Docker installed"
fi

# Start dockerd if not running
if ! pgrep -x dockerd > /dev/null; then
    echo "  Starting Docker daemon..."
    pkill -f dockerd 2>/dev/null || true
    sleep 2
    dockerd --iptables=false > /var/log/dockerd.log 2>&1 &

    # Wait for Docker to be ready
    for i in {1..30}; do
        if docker info &> /dev/null; then
            echo "  ✓ Docker daemon ready"
            break
        fi
        sleep 1
        if [ $i -eq 30 ]; then
            echo "  ❌ Docker daemon failed to start"
            exit 1
        fi
    done
fi

echo ""

# ===================================================================
# 2. Install k3s Binary
# ===================================================================
echo "Step 2/5: Installing k3s..."

if [ -f "/usr/local/bin/k3s" ]; then
    echo "  ✓ k3s already installed ($(k3s --version | head -1))"
else
    echo "  Extracting k3s from Docker image..."

    # Pull k3s image
    docker pull rancher/k3s:v1.28.5-k3s1 > /dev/null 2>&1

    # Extract k3s binary
    CONTAINER=$(docker create rancher/k3s:v1.28.5-k3s1)
    docker cp $CONTAINER:/bin/k3s /usr/local/bin/k3s
    docker rm $CONTAINER > /dev/null 2>&1

    chmod +x /usr/local/bin/k3s

    echo "  ✓ k3s installed ($(k3s --version | head -1))"
fi

echo ""

# ===================================================================
# 3. Create kubectl Symlink
# ===================================================================
echo "Step 3/5: Setting up kubectl..."

if [ -L "/usr/local/bin/kubectl" ]; then
    echo "  ✓ kubectl symlink already exists"
else
    ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
    echo "  ✓ kubectl symlink created"
fi

echo ""

# ===================================================================
# 4. Setup Fake CNI Plugin (Experiment 05 Breakthrough)
# ===================================================================
echo "Step 4/5: Setting up fake CNI plugin..."

mkdir -p /opt/cni/bin

if [ -f "/opt/cni/bin/host-local" ]; then
    echo "  ✓ Fake CNI plugin already exists"
else
    cat > /opt/cni/bin/host-local << 'EOFCNI'
#!/bin/bash
# Minimal fake CNI plugin for control-plane-only mode
# Returns valid JSON to satisfy k3s initialization checks
echo '{"cniVersion": "0.4.0", "ips": [{"version": "4", "address": "10.244.0.1/24"}]}'
exit 0
EOFCNI
    chmod +x /opt/cni/bin/host-local
    echo "  ✓ Fake CNI plugin created"
fi

# Add to PATH
export PATH="/opt/cni/bin:$PATH"

echo ""

# ===================================================================
# 5. Install Helm (optional but useful)
# ===================================================================
echo "Step 5/5: Checking Helm..."

if command -v helm &> /dev/null; then
    echo "  ✓ Helm already installed ($(helm version --short))"
else
    echo "  Helm not installed (skipping - not required for experiments)"
fi

echo ""

# ===================================================================
# Setup Complete
# ===================================================================
echo "====================================================================="
echo "✅ Setup Complete!"
echo "====================================================================="
echo ""
echo "Installed Components:"
echo "  • Docker: $(docker --version)"
echo "  • k3s: $(k3s --version | head -1)"
echo "  • kubectl: Available (symlink to k3s)"
echo "  • Fake CNI: /opt/cni/bin/host-local"
echo ""
echo "Environment Variables:"
echo "  export PATH=\"/opt/cni/bin:\$PATH\""
echo "  export KUBECONFIG=\"/etc/rancher/k3s/k3s.yaml\""
echo ""
echo "Next Steps:"
echo "  1. Start k3s control-plane:"
echo "      bash solutions/control-plane-native/start-k3s-native.sh"
echo ""
echo "  2. Test with kubectl:"
echo "      export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
echo "      kubectl get namespaces"
echo ""
echo "  3. Run experiments:"
echo "      See TESTING-GUIDE.md for experiment procedures"
echo ""
echo "====================================================================="
