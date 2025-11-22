#!/bin/bash

# Start k3s cluster for development using unshare for proper mount propagation
# This bypasses Docker container restrictions and allows worker nodes to function

set -e

echo "Starting k3s cluster with worker node support..."

# Check if k3s is already running
if pgrep -f "k3s server" > /dev/null; then
    echo "✓ k3s is already running"
    exit 0
fi

# Ensure CNI plugins are accessible
export PATH="/opt/cni/bin:/usr/local/bin:/usr/bin:/bin"

# Configure kubeconfig location (will be in tmpfs data directory)
export KUBECONFIG="/mnt/k3s-tmpfs/server/cred/admin.kubeconfig"

# Create fake /proc/diskstats for cAdvisor (sandboxed environment doesn't have it)
if [ ! -f /proc/diskstats ]; then
    echo "Creating fake /proc/diskstats for cAdvisor..."
    cat > /tmp/diskstats << 'DISKSTATS'
   8       0 sda 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
   8       1 sda1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
 253       0 dm-0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
DISKSTATS
    chmod 444 /tmp/diskstats
fi

echo "Starting k3s server in mount namespace with shared propagation..."
echo "Note: This enables worker nodes by bypassing container mount restrictions"
echo ""

# Start k3s in unshared mount namespace with shared mount propagation
# This is the KEY to making worker nodes work in sandboxed environments
# Use /tmp for PID file to ensure it's accessible from both namespaces
PID_FILE="/tmp/k3s.pid"
rm -f "$PID_FILE"

unshare --mount --propagation unchanged /bin/bash -c "
    # Fake /dev/kmsg for kubelet OOM watcher (bind-mount /dev/null)
    # This is the same approach used by Kubernetes-in-Docker (kind)
    if [ ! -e /dev/kmsg ]; then
        touch /dev/kmsg 2>/dev/null || true
    fi
    mount --bind /dev/null /dev/kmsg 2>/dev/null || echo \"Note: Could not bind-mount /dev/kmsg\"

    # Make root mount propagation shared - this allows kubelet to work
    mount --make-rshared / 2>/dev/null || echo \"Note: mount propagation already configured\"

    # Mount tmpfs on k3s data directory so cAdvisor sees a supported filesystem
    # This is the KEY - cAdvisor needs a real filesystem, not 9p
    mkdir -p /mnt/k3s-tmpfs
    mount -t tmpfs -o size=20G tmpfs /mnt/k3s-tmpfs 2>/dev/null || echo \"Note: Could not mount tmpfs\"
    mount --make-rshared /mnt/k3s-tmpfs 2>/dev/null || true

    # Mount fake diskstats for cAdvisor
    touch /proc/diskstats 2>/dev/null || true
    mount --bind /tmp/diskstats /proc/diskstats 2>/dev/null || echo \"Note: Could not mount diskstats\"

    # Start k3s server with worker node support
    # Use tmpfs data directory to avoid 9p filesystem issues with cAdvisor
    nohup k3s server \
        --data-dir=/mnt/k3s-tmpfs \
        --https-listen-port=6443 \
        --disable=traefik \
        --disable=servicelb \
        --write-kubeconfig-mode=644 \
        --snapshotter=native \
        --kubelet-arg=\"--fail-swap-on=false\" \
        --kubelet-arg=\"--cgroups-per-qos=false\" \
        --kubelet-arg=\"--enforce-node-allocatable=\" \
        --kubelet-arg=\"--protect-kernel-defaults=false\" \
        --kubelet-arg=\"--image-gc-high-threshold=100\" \
        --kubelet-arg=\"--image-gc-low-threshold=99\" \
        --kubelet-arg=\"--minimum-image-ttl-duration=0\" \
        --kubelet-arg=\"--eviction-hard=\" \
        --kubelet-arg=\"--eviction-soft=\" \
        > /var/log/k3s.log 2>&1 &

    # Write k3s server PID to file accessible from parent namespace
    K3S_SERVER_PID=\$!
    echo \$K3S_SERVER_PID > $PID_FILE
    # Also write to /var/run for compatibility
    echo \$K3S_SERVER_PID > /var/run/k3s.pid
" &

# Wait for PID file to be created (with timeout)
UNSHARE_PID=$!
echo "unshare process started with PID: $UNSHARE_PID"

for i in {1..10}; do
    if [ -f "$PID_FILE" ]; then
        K3S_PID=$(cat "$PID_FILE")
        echo "k3s started with PID: $K3S_PID"
        # Verify the process is actually running
        if ps -p "$K3S_PID" > /dev/null 2>&1; then
            break
        else
            echo "⚠ PID $K3S_PID not found in process list, waiting..."
        fi
    fi
    sleep 0.5
    if [ $i -eq 10 ]; then
        echo "⚠ Could not determine k3s PID after 5 seconds"
        echo "   Attempting to find k3s process..."
        # Fallback: try to find k3s process
        FOUND_PID=$(pgrep -f "k3s server" | head -1)
        if [ -n "$FOUND_PID" ]; then
            echo "   Found k3s process with PID: $FOUND_PID"
            echo "$FOUND_PID" > "$PID_FILE"
            echo "$FOUND_PID" > /var/run/k3s.pid
        fi
    fi
done

# Wait for kubeconfig to be created
echo "Waiting for kubeconfig..."
for i in {1..60}; do
    if [ -f "$KUBECONFIG" ]; then
        echo "✓ Kubeconfig created"
        break
    fi
    sleep 1
    if [ $i -eq 60 ]; then
        echo "⚠ Timeout waiting for kubeconfig"
        echo "Check logs: tail -f /var/log/k3s.log"
        exit 1
    fi
done

# Wait for API server to be ready
echo "Waiting for API server..."
for i in {1..60}; do
    if kubectl get --raw /healthz &> /dev/null; then
        echo "✓ API server is ready"
        break
    fi
    sleep 1
    if [ $i -eq 60 ]; then
        echo "⚠ API server not responding"
        echo "k3s may have issues in this environment"
        echo "Check logs: tail -f /var/log/k3s.log"
        exit 1
    fi
done

# Wait for node to be ready
echo "Waiting for node to be ready..."
for i in {1..60}; do
    if kubectl get nodes 2>/dev/null | grep -q " Ready"; then
        echo "✓ k3s cluster is ready with worker node!"
        kubectl get nodes
        echo ""
        echo "Kubeconfig: $KUBECONFIG"
        echo "To use kubectl: export KUBECONFIG=$KUBECONFIG"
        exit 0
    fi
    sleep 1
    if [ $i -eq 60 ]; then
        echo "⚠ Node not ready after 60 seconds"
        echo "Cluster may still be initializing"
        kubectl get nodes 2>/dev/null || echo "No nodes found yet"
        echo "Check status with: kubectl get nodes"
        echo "Check logs: tail -f /var/log/k3s.log"
        exit 1
    fi
done

