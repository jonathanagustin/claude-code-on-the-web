#!/bin/bash

# Automated Docker Network State Cleanup
# Removes all Docker networking state to enable fresh bridge creation

set -e

echo "=========================================="
echo "Docker Network State Cleanup"
echo "=========================================="
echo

# Stop Docker if running
echo "Step 1: Stopping Docker daemon..."
pkill dockerd 2>/dev/null || echo "Docker not running"
sleep 3

# Remove all network namespaces created by Docker
echo "Step 2: Removing network namespaces..."
if [ -d /var/run/netns ]; then
    for ns in $(ip netns list 2>/dev/null | awk '{print $1}'); do
        echo "  - Removing namespace: $ns"
        ip netns del "$ns" 2>/dev/null || true
    done
fi

# Remove Docker network interfaces
echo "Step 3: Removing Docker network interfaces..."
INTERFACES=$(ip link show | grep -E 'docker|br-|veth' | awk '{print $2}' | sed 's/:$//' | sed 's/@.*$//')

for iface in $INTERFACES; do
    echo "  - Removing interface: $iface"
    ip link del "$iface" 2>/dev/null || true
done

# Remove Docker network state files
echo "Step 4: Removing Docker network state files..."
rm -rf /var/lib/docker/network/* 2>/dev/null || true

# Remove Docker network database
echo "Step 5: Removing Docker network database..."
rm -f /var/lib/docker/network.db 2>/dev/null || true
rm -f /var/lib/docker/network/files/* 2>/dev/null || true

# Verify cleanup
echo
echo "Step 6: Verifying cleanup..."
REMAINING=$(ip link show | grep -E 'docker|br-.*veth' || true)

if [ -z "$REMAINING" ]; then
    echo "✅ All Docker network interfaces removed"
else
    echo "⚠️  Some interfaces remain:"
    echo "$REMAINING"
fi

echo
echo "=========================================="
echo "Cleanup Complete!"
echo "=========================================="
echo
echo "You can now start Docker with a clean network state:"
echo "  LD_PRELOAD=/tmp/netlink_intercept_v2.so dockerd --iptables=false"
