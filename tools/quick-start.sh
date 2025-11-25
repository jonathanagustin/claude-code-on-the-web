#!/bin/bash

# Quick Start Script for Kubernetes Research Environment
# Auto-starts the production-ready control-plane solution

set -e

echo "========================================================"
echo "Kubernetes in gVisor - Quick Start"
echo "Production-Ready Control-Plane (Experiment 05)"
echo "========================================================"
echo ""

# Check if already running
if pgrep -f "k3s server" > /dev/null; then
    echo "✓ k3s is already running"
    echo ""
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    echo "Cluster status:"
    kubectl get nodes 2>/dev/null || echo "  (waiting for k3s to be ready...)"
    kubectl get namespaces 2>/dev/null | head -5 || true
    echo ""
    echo "Ready for development!"
    exit 0
fi

echo "Starting k3s control-plane..."
echo ""

# Start the control-plane
if [ -f "solutions/control-plane-native/start-k3s-native.sh" ]; then
    bash solutions/control-plane-native/start-k3s-native.sh
else
    echo "ERROR: Control-plane script not found"
    echo "Expected: solutions/control-plane-native/start-k3s-native.sh"
    exit 1
fi

echo ""
echo "========================================================"
echo "Control-Plane Started Successfully!"
echo "========================================================"
echo ""

# Configure kubectl
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Wait for k3s to be ready
echo "Waiting for k3s to be ready..."
for i in {1..30}; do
    if kubectl get nodes &>/dev/null; then
        echo "✓ k3s is ready!"
        break
    fi
    sleep 1
done

echo ""
echo "Cluster status:"
kubectl get nodes
echo ""
kubectl get namespaces
echo ""

echo "========================================================"
echo "Quick Start Examples"
echo "========================================================"
echo ""
echo "Create a Helm chart:"
echo "  helm create mychart"
echo "  helm install test ./mychart/"
echo "  kubectl get all"
echo ""
echo "Validate YAML:"
echo "  kubectl apply -f deployment.yaml --dry-run=server"
echo ""
echo "Test RBAC:"
echo "  kubectl auth can-i list pods --as=system:serviceaccount:default:myapp"
echo ""
echo "Note: Pod execution is not available (requires real kernel cgroup subsystem)"
echo "      See PROGRESS-SUMMARY.md for full research findings"
echo ""
