#!/bin/bash

# Combined setup script for Claude Code on the web environment
# This script orchestrates the installation of all tools needed for
# Kubernetes development in a sandboxed Claude Code web environment

set -e

echo "========================================================"
echo "Claude Code Environment Setup"
echo "========================================================"
echo ""
echo "This script will install:"
echo "  1. Container runtime (Podman, Docker CLI, Buildah)"
echo "  2. Kubernetes tools (k3s, kubectl, containerd)"
echo "  3. Additional tools (helm, kubectx)"
echo ""
echo "Installation method: Binary extraction from container images"
echo "This bypasses GitHub download restrictions in the environment"
echo ""

# Only run in remote (web) environments
if [ "$CLAUDE_CODE_REMOTE" != "true" ]; then
  echo "Skipping setup (running locally)"
  exit 0
fi

INSTALL_ERRORS=0

# =============================================================================
# STEP 1: Install Container Runtime
# =============================================================================
echo "================================================"
echo "Step 1/3: Installing Container Runtime"
echo "================================================"

if command -v podman &> /dev/null; then
    echo "✓ Podman is already installed"
    podman --version
else
    echo "Installing Podman and container tools..."
    export DEBIAN_FRONTEND=noninteractive
    echo "Updating package lists..."
    apt-get update -qq 2>&1 | grep -v "Failed to fetch\|An error occurred during the signature verification" || true

    echo "Installing: podman, podman-docker, buildah, docker-compose..."
    apt-get install -y -qq \
        podman \
        podman-docker \
        buildah \
        docker-compose \
        crun \
        fuse-overlayfs \
        slirp4netns \
        containernetworking-plugins 2>&1 | grep -v "debconf: delaying package configuration" || true

    # Create nodocker file to suppress Docker emulation messages
    if [ ! -f /etc/containers/nodocker ]; then
        mkdir -p /etc/containers
        touch /etc/containers/nodocker
    fi

    # Configure Podman registries for unqualified searches
    if ! grep -q "unqualified-search-registries.*docker.io" /etc/containers/registries.conf 2>/dev/null; then
        echo "Configuring Podman registries for unqualified searches..."
        cat >> /etc/containers/registries.conf << 'EOF'

# Unqualified image search registries
unqualified-search-registries = ["docker.io", "ghcr.io", "quay.io", "gcr.io", "registry.k8s.io"]
EOF
    fi

    echo "✓ Container runtime installed"
    echo "  - Podman: $(podman --version | head -1)"
    echo "  - Docker CLI: Available (emulated via Podman)"
    echo "  - Buildah: $(buildah --version | head -1)"
fi

# =============================================================================
# STEP 2: Install k3s and kubectl
# =============================================================================
echo ""
echo "================================================"
echo "Step 2/3: Installing k3s/kubectl/containerd"
echo "================================================"

if command -v k3s &> /dev/null && command -v kubectl &> /dev/null; then
    if k3s --version &> /dev/null && kubectl version --client &> /dev/null; then
        echo "✓ k3s and kubectl are already installed"
        echo "  - k3s: $(k3s --version | head -1)"
        echo "  - kubectl: $(kubectl version --client | head -1)"
    else
        echo "⚠ k3s/kubectl found but not functional, reinstalling..."
        rm -f /usr/local/bin/k3s /usr/local/bin/kubectl /usr/local/bin/containerd
    fi
fi

if ! command -v k3s &> /dev/null; then
    echo "Pulling k3s container image..."
    podman pull docker.io/rancher/k3s:latest

    echo "Extracting k3s binary from container image..."
    TEMP_DIR=$(mktemp -d)
    trap "cd / && rm -rf '${TEMP_DIR}'" EXIT ERR

    cd "${TEMP_DIR}"

    # Save container image as tar
    podman save docker.io/rancher/k3s:latest -o k3s-image.tar
    tar -xf k3s-image.tar

    # Find the layer.tar file
    LAYER_TAR=$(find . -name "layer.tar" | head -1)

    if [ -z "$LAYER_TAR" ]; then
        echo "ERROR: Could not find layer.tar in the image"
        exit 1
    fi

    # Extract k3s binary
    tar -xf "${LAYER_TAR}" bin/k3s
    cp bin/k3s /usr/local/bin/k3s
    chmod +x /usr/local/bin/k3s

    # Create kubectl symlink (k3s is a multi-call binary)
    ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl

    # Create containerd symlink (k3s includes containerd)
    ln -sf /usr/local/bin/k3s /usr/local/bin/containerd

    # Extract and install containerd-shim-runc-v2
    if tar -xf "${LAYER_TAR}" bin/containerd-shim-runc-v2 2>/dev/null; then
        cp bin/containerd-shim-runc-v2 /usr/local/bin/
        chmod +x /usr/local/bin/containerd-shim-runc-v2
    fi

    # Setup CNI plugins - CRITICAL: Must copy binaries, symlinks don't work with k3s
    mkdir -p /opt/cni/bin
    if [ -d /usr/lib/cni ] && [ ! -f /opt/cni/bin/host-local ]; then
        echo "Copying CNI plugin binaries to /opt/cni/bin/..."
        cp /usr/lib/cni/* /opt/cni/bin/
        chmod +x /opt/cni/bin/*
    fi

    cd /
    rm -rf "${TEMP_DIR}"

    echo "✓ k3s/kubectl/containerd installed"
    echo "  - k3s: $(k3s --version | head -1)"
    echo "  - kubectl: $(kubectl version --client | head -1)"
    echo "  - containerd: $(containerd --version)"
fi

# =============================================================================
# STEP 3: Install Kubernetes Tools
# =============================================================================
echo ""
echo "================================================"
echo "Step 3/3: Installing Kubernetes Tools"
echo "================================================"

# Install system utilities for research
echo "Installing system utilities (inotify-tools, strace, etc.)..."
if apt-get install -y -qq inotify-tools strace lsof 2>&1 | grep -v "debconf"; then
    echo "✓ System utilities installed"
else
    echo "⚠ Failed to install some system utilities"
    INSTALL_ERRORS=$((INSTALL_ERRORS + 1))
fi

# Install kubectx/kubens
if ! command -v kubectx &> /dev/null; then
    echo "Installing kubectx/kubens..."
    if apt-get update -qq 2>&1 | grep -v "Failed to fetch" && apt-get install -y -qq kubectx 2>&1 | grep -v "debconf"; then
        echo "✓ kubectx and kubens installed"
    else
        echo "⚠ Failed to install kubectx/kubens"
        INSTALL_ERRORS=$((INSTALL_ERRORS + 1))
    fi
else
    echo "✓ kubectx already installed"
fi

# Install helm
if ! command -v helm &> /dev/null; then
    echo "Installing helm from container image..."
    if podman pull docker.io/dtzar/helm-kubectl:latest 2>&1 | grep -v "Trying to pull"; then
        TEMP_DIR=$(mktemp -d)
        cd "${TEMP_DIR}"

        podman save docker.io/dtzar/helm-kubectl:latest -o helm-image.tar
        tar -xf helm-image.tar

        HELM_INSTALLED=false
        for layer in */layer.tar; do
            if tar -tf "$layer" 2>/dev/null | grep -q "usr/local/bin/helm"; then
                tar -xf "$layer" usr/local/bin/helm
                cp usr/local/bin/helm /usr/local/bin/helm
                chmod +x /usr/local/bin/helm
                echo "✓ helm installed ($(helm version --short))"
                HELM_INSTALLED=true
                break
            fi
        done

        if [ "$HELM_INSTALLED" = false ]; then
            echo "⚠ Could not extract helm binary from image"
            INSTALL_ERRORS=$((INSTALL_ERRORS + 1))
        fi

        cd /
        rm -rf "${TEMP_DIR}"
    else
        echo "⚠ Failed to pull helm image"
        INSTALL_ERRORS=$((INSTALL_ERRORS + 1))
    fi
else
    echo "✓ helm already installed ($(helm version --short))"
fi

# Install helm-unittest plugin
if ! helm plugin list 2>/dev/null | grep -q unittest; then
    echo "Installing helm-unittest plugin..."
    if helm plugin install https://github.com/helm-unittest/helm-unittest --verify=false 2>&1 | grep -v "WARNING"; then
        echo "✓ helm-unittest plugin installed"
    else
        echo "⚠ Failed to install helm-unittest plugin (network may be restricted)"
        INSTALL_ERRORS=$((INSTALL_ERRORS + 1))
    fi
else
    echo "✓ helm-unittest plugin already installed"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "========================================================"
echo "Claude Code Environment Setup Complete!"
echo "========================================================"
echo ""
echo "Installed Tools:"
echo "  Container Runtime:"
echo "    - podman $(podman --version | awk '{print $3}')"
echo "    - docker (CLI emulated via Podman)"
echo "    - buildah $(buildah --version | awk '{print $3}')"
echo ""
echo "  Kubernetes Core:"
echo "    - k3s $(k3s --version | awk '{print $3}')"
echo "    - kubectl $(kubectl version --client --short 2>/dev/null | awk '{print $3}' || echo 'installed')"
echo "    - containerd (embedded in k3s)"
echo ""
echo "  Development Tools:"
command -v helm &> /dev/null && echo "    - helm $(helm version --short)"
helm plugin list 2>/dev/null | grep -q unittest && echo "    - helm-unittest (for chart testing)"
command -v kubectx &> /dev/null && echo "    - kubectx/kubens (context switching)"
echo ""
echo "  Research Tools:"
command -v inotifywait &> /dev/null && echo "    - inotify-tools (real-time file monitoring)"
command -v strace &> /dev/null && echo "    - strace (syscall tracing)"
command -v lsof &> /dev/null && echo "    - lsof (file/process inspection)"
echo ""
echo "Next Steps:"
echo "  - Start k3s control-plane: sudo bash solutions/control-plane-native/start-k3s-native.sh"
echo "  - Use 'kubectl' for Kubernetes operations"
echo "  - Use 'helm' for package management"
echo "  - See PROGRESS-SUMMARY.md for research findings"
echo ""

if [ $INSTALL_ERRORS -gt 0 ]; then
    echo "⚠ Warning: $INSTALL_ERRORS optional tool(s) failed to install"
    echo "Core functionality is still available"
fi

echo "========================================================"
exit 0

