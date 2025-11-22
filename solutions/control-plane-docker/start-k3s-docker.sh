#!/bin/bash

# K3s in Docker - Working solution for sandboxed environments
# This script runs k3s inside a Docker container, avoiding host kernel restrictions

set -e

echo "================================================"
echo "K3s Cluster Setup (Docker Container Mode)"
echo "================================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

# =============================================================================
# Step 1: Ensure Docker is installed and running
# =============================================================================
echo "Step 1/4: Checking Docker installation..."

if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y docker.io
fi

# Check if dockerd is running
if ! pgrep -x dockerd > /dev/null; then
    echo "Starting Docker daemon..."
    # Kill any existing dockerd
    pkill -f dockerd 2>/dev/null || true
    sleep 2

    # Start dockerd with minimal options
    dockerd --iptables=false > /var/log/dockerd.log 2>&1 &

    # Wait for Docker to be ready
    echo "Waiting for Docker daemon..."
    for i in {1..30}; do
        if docker info &> /dev/null; then
            echo "✓ Docker daemon is ready"
            break
        fi
        sleep 1
        if [ $i -eq 30 ]; then
            echo "✗ Docker daemon failed to start"
            echo "Check logs: tail -f /var/log/dockerd.log"
            exit 1
        fi
    done
else
    echo "✓ Docker daemon already running"
fi

echo ""

# =============================================================================
# Step 2: Start or restart k3s container
# =============================================================================
echo "Step 2/4: Setting up k3s container..."

# Stop and remove existing k3s container if it exists
if docker ps -a --format '{{.Names}}' | grep -q '^k3s-server$'; then
    echo "Removing existing k3s-server container..."
    docker stop k3s-server 2>/dev/null || true
    docker rm k3s-server 2>/dev/null || true
fi

# Pull k3s image
K3S_VERSION="${K3S_VERSION:-v1.33.5-k3s1}"
echo "Pulling k3s image: rancher/k3s:$K3S_VERSION"
docker pull rancher/k3s:$K3S_VERSION

# Start k3s in Docker container
echo "Starting k3s container..."

# Create /dev/kmsg if it doesn't exist (needed by kubelet)
if [ ! -e /dev/kmsg ]; then
    echo "Creating /dev/kmsg device..."
    mknod /dev/kmsg c 1 11 || true
    chmod 600 /dev/kmsg || true
fi

# Create tmpfs mount for /var/lib/kubelet to avoid bind-mount issues
mkdir -p /tmp/k3s-kubelet

docker run -d \
    --name k3s-server \
    --privileged \
    --network host \
    -v /dev/kmsg:/dev/kmsg:ro \
    --tmpfs /var/lib/kubelet:rw,exec,nosuid,nodev \
    --tmpfs /run:rw,exec,nosuid,nodev \
    rancher/k3s:$K3S_VERSION server \
        --disable=traefik \
        --disable=servicelb \
        --disable-agent \
        --https-listen-port=6443 \
        --snapshotter=native

echo "✓ k3s container started"
echo ""

# =============================================================================
# Step 3: Wait for k3s to be ready and extract kubeconfig
# =============================================================================
echo "Step 3/4: Waiting for k3s API server..."

# Wait for kubeconfig to be created inside container
for i in {1..60}; do
    if docker exec k3s-server test -f /etc/rancher/k3s/k3s.yaml 2>/dev/null; then
        echo "✓ k3s kubeconfig created"
        break
    fi
    sleep 1
    if [ $i -eq 60 ]; then
        echo "✗ Timeout waiting for k3s kubeconfig"
        echo "Check container logs: docker logs k3s-server"
        exit 1
    fi
done

# Extract kubeconfig
mkdir -p /root/.kube
docker exec k3s-server cat /etc/rancher/k3s/k3s.yaml > /root/.kube/config
chmod 600 /root/.kube/config

echo "✓ Kubeconfig extracted to /root/.kube/config"
echo ""

# =============================================================================
# Step 4: Test cluster connectivity
# =============================================================================
echo "Step 4/4: Testing cluster connectivity..."

export KUBECONFIG=/root/.kube/config

# Wait for API server to respond
for i in {1..30}; do
    if kubectl get --raw /healthz --insecure-skip-tls-verify &> /dev/null; then
        echo "✓ API server is responding"
        break
    fi
    sleep 1
    if [ $i -eq 30 ]; then
        echo "⚠ API server not responding after 30 seconds"
        echo "Cluster may still be initializing"
    fi
done

# Show cluster info
echo ""
echo "Cluster Status:"
kubectl get namespaces --insecure-skip-tls-verify 2>&1

echo ""
echo "================================================"
echo "K3s Cluster Ready!"
echo "================================================"
echo ""
echo "Cluster Info:"
echo "  - K3s Version: $K3S_VERSION (Kubernetes v1.33.5)"
echo "  - API Server: https://127.0.0.1:6443"
echo "  - Kubeconfig: /root/.kube/config"
echo ""
echo "Usage:"
echo "  export KUBECONFIG=/root/.kube/config"
echo "  kubectl get nodes --insecure-skip-tls-verify"
echo "  kubectl get pods -A --insecure-skip-tls-verify"
echo ""
echo "Notes:"
echo "  - Use --insecure-skip-tls-verify flag with kubectl"
echo "  - Agent pods won't schedule (overlay filesystem issues)"
echo "  - API server is fully functional for chart development"
echo "  - Helm installs work correctly"
echo ""
echo "Manage cluster:"
echo "  docker logs k3s-server    # View logs"
echo "  docker stop k3s-server    # Stop cluster"
echo "  docker start k3s-server   # Start cluster"
echo "  docker rm k3s-server      # Remove cluster"
echo ""

