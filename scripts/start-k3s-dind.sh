#!/bin/bash

# K3s Docker-in-Docker (DinD) Setup Script
# Attempts to run k3s with worker nodes in a sandboxed environment

set -e

echo "================================================"
echo "K3s DinD Setup (Experimental)"
echo "================================================"
echo ""

# Configuration
K3S_VERSION="${K3S_VERSION:-v1.33.5-k3s1}"
CONTAINER_NAME="k3s-dind"
MODE="${1:-default}"  # Options: default, docker-runtime, privileged-all

# Color codes for output
RED='\033[0:31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Cleanup function
cleanup() {
    echo "Cleaning up existing k3s containers..."
    docker rm -f $CONTAINER_NAME 2>/dev/null || true
}

# Check if Docker daemon is running
check_docker() {
    echo "Step 1/5: Checking Docker daemon..."
    if ! docker info > /dev/null 2>&1; then
        echo "Docker daemon not running. Starting..."
        dockerd --iptables=false --ip6tables=false > /var/log/dockerd.log 2>&1 &
        sleep 5
        if ! docker info > /dev/null 2>&1; then
            echo -e "${RED}✗ Failed to start Docker daemon${NC}"
            exit 1
        fi
    fi
    echo -e "${GREEN}✓ Docker daemon is running${NC}"
    echo ""
}

# Mode 1: Default (containerd, with cgroup access)
mode_default() {
    echo "Starting k3s with containerd runtime..."
    echo "Features: cgroup access, native snapshotter, disabled agent enforcement"
    echo ""

    docker run -d \
        --name $CONTAINER_NAME \
        --privileged \
        --cgroupns=host \
        --network host \
        --pid host \
        -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
        -v /dev/kmsg:/dev/kmsg:ro \
        rancher/k3s:$K3S_VERSION server \
            --disable=traefik \
            --disable=servicelb \
            --https-listen-port=6443 \
            --snapshotter=native \
            --kubelet-arg="--fail-swap-on=false" \
            --kubelet-arg="--cgroups-per-qos=false" \
            --kubelet-arg="--enforce-node-allocatable=" \
            --kubelet-arg="--protect-kernel-defaults=false"
}

# Mode 2: Docker runtime with cri-dockerd
mode_docker_runtime() {
    echo "Starting k3s with Docker runtime..."
    echo "Features: Docker socket mount, cri-dockerd interface"
    echo ""

    if [ ! -S /var/run/docker.sock ]; then
        echo -e "${RED}✗ Docker socket not found${NC}"
        exit 1
    fi

    docker run -d \
        --name $CONTAINER_NAME \
        --privileged \
        --cgroupns=host \
        --network host \
        --pid host \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
        -v /dev/kmsg:/dev/kmsg:ro \
        rancher/k3s:$K3S_VERSION server \
            --disable=traefik \
            --disable=servicelb \
            --https-listen-port=6443 \
            --docker \
            --kubelet-arg="--fail-swap-on=false" \
            --kubelet-arg="--cgroups-per-qos=false" \
            --kubelet-arg="--enforce-node-allocatable="
}

# Mode 3: Privileged with all capabilities
mode_privileged_all() {
    echo "Starting k3s with maximum privileges..."
    echo "Features: all capabilities, apparmor unconfined, shared cgroups"
    echo ""

    docker run -d \
        --name $CONTAINER_NAME \
        --privileged \
        --security-opt apparmor:unconfined \
        --security-opt seccomp=unconfined \
        --cap-add=ALL \
        --cgroupns=host \
        --network host \
        --pid host \
        --ipc host \
        -v /sys:/sys:rw \
        -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
        -v /dev:/dev:rw \
        -v /lib/modules:/lib/modules:ro \
        rancher/k3s:$K3S_VERSION server \
            --disable=traefik \
            --disable=servicelb \
            --https-listen-port=6443 \
            --snapshotter=native \
            --kubelet-arg="--fail-swap-on=false" \
            --kubelet-arg="--cgroups-per-qos=false" \
            --kubelet-arg="--enforce-node-allocatable=" \
            --kubelet-arg="--protect-kernel-defaults=false" \
            --kubelet-arg="--v=5"
}

# Main execution
main() {
    check_docker
    cleanup

    echo "Step 2/5: Pulling k3s image..."
    docker pull rancher/k3s:$K3S_VERSION
    echo ""

    echo "Step 3/5: Starting k3s container (mode: $MODE)..."
    case "$MODE" in
        docker-runtime)
            mode_docker_runtime
            ;;
        privileged-all)
            mode_privileged_all
            ;;
        default|*)
            mode_default
            ;;
    esac
    echo -e "${GREEN}✓ Container started${NC}"
    echo ""

    echo "Step 4/5: Waiting for API server..."
    for i in {1..30}; do
        if docker exec $CONTAINER_NAME test -f /etc/rancher/k3s/k3s.yaml 2>/dev/null; then
            echo -e "${GREEN}✓ Kubeconfig created${NC}"
            break
        fi
        sleep 1
        if [ $i -eq 30 ]; then
            echo -e "${YELLOW}⚠ Timeout waiting for kubeconfig${NC}"
            echo "Check logs: docker logs $CONTAINER_NAME"
            exit 1
        fi
    done
    echo ""

    echo "Step 5/5: Extracting kubeconfig and testing..."
    docker exec $CONTAINER_NAME cat /etc/rancher/k3s/k3s.yaml > /root/.kube/config 2>/dev/null || true

    # Wait for API server
    sleep 5

    # Check if container is still running
    if ! docker ps | grep -q $CONTAINER_NAME; then
        echo -e "${RED}✗ Container crashed${NC}"
        echo ""
        echo "Last 30 lines of logs:"
        docker logs $CONTAINER_NAME 2>&1 | tail -30
        echo ""
        echo "Common errors:"
        docker logs $CONTAINER_NAME 2>&1 | grep -i "error\|failed" | tail -10
        exit 1
    fi

    # Try to get nodes
    echo "Checking for worker nodes..."
    if docker exec $CONTAINER_NAME kubectl get nodes 2>&1 | grep -q "Ready\|NotReady"; then
        echo -e "${GREEN}✓ Worker node detected!${NC}"
        docker exec $CONTAINER_NAME kubectl get nodes
        success=true
    else
        echo -e "${YELLOW}⚠ No worker nodes (control-plane only mode)${NC}"
        success=false
    fi

    echo ""
    echo "================================================"
    if [ "$success" = true ]; then
        echo -e "${GREEN}K3s DinD Success! 🎉${NC}"
    else
        echo -e "${YELLOW}K3s DinD Partial Success${NC}"
    fi
    echo "================================================"
    echo ""
    echo "Cluster Info:"
    echo "  - K3s Version: $K3S_VERSION"
    echo "  - Mode: $MODE"
    echo "  - Container: $CONTAINER_NAME"
    echo "  - API Server: https://127.0.0.1:6443"
    echo ""
    echo "Usage:"
    echo "  export KUBECONFIG=/root/.kube/config"
    echo "  kubectl get nodes"
    echo "  docker exec $CONTAINER_NAME kubectl get nodes"
    echo ""
    echo "Logs:"
    echo "  docker logs $CONTAINER_NAME"
    echo "  docker logs $CONTAINER_NAME 2>&1 | grep -i error"
    echo ""
    echo "Cleanup:"
    echo "  docker rm -f $CONTAINER_NAME"
    echo ""

    # Show specific errors if any
    if [ "$success" = false ]; then
        echo "Detected Issues:"
        docker logs $CONTAINER_NAME 2>&1 | grep "bind-mount" && \
            echo "  - bind-mount error (kubelet limitation in sandbox)"
        docker logs $CONTAINER_NAME 2>&1 | grep "cri-dockerd" && \
            echo "  - cri-dockerd missing (Docker runtime requires cri-dockerd)"
        echo ""
        echo "Note: Sandbox environments have fundamental limitations"
        echo "preventing worker nodes. Consider using control-plane-only"
        echo "mode via scripts/start-k3s-docker.sh instead."
    fi
}

# Show usage
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [MODE]"
    echo ""
    echo "Modes:"
    echo "  default          - Containerd runtime with cgroup access (default)"
    echo "  docker-runtime   - Docker runtime with cri-dockerd"
    echo "  privileged-all   - Maximum privileges (all caps, apparmor unconfined)"
    echo ""
    echo "Examples:"
    echo "  $0                      # Use default mode"
    echo "  $0 docker-runtime       # Try Docker runtime"
    echo "  $0 privileged-all        # Try maximum privileges"
    echo ""
    echo "Environment Variables:"
    echo "  K3S_VERSION      - K3s version to use (default: v1.33.5-k3s1)"
    echo ""
    exit 0
fi

main

