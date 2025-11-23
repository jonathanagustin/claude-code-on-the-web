#!/bin/bash

echo "=== Final Bridge Networking Test ==="
echo

# Stop existing Docker
pkill dockerd
sleep 3

# Start Docker with enhanced interceptor
echo "Starting Docker with enhanced netlink interceptor..."
LD_PRELOAD=/tmp/netlink_intercept_v2.so dockerd --iptables=false > /var/log/dockerd-v2.log 2>&1 &
DOCKER_PID=$!

sleep 10

# Test if Docker is running
if docker info > /dev/null 2>&1; then
    echo "✅ Docker is running"

    # Try bridge networking
    echo
    echo "Testing bridge networking..."
    docker run --rm --network bridge rancher/k3s:v1.33.5-k3s1 echo "🎉 BRIDGE NETWORKING WORKS!"
    RESULT=$?

    echo
    if [ $RESULT -eq 0 ]; then
        echo "✅✅✅ BREAKTHROUGH SUCCESS! ✅✅✅"
        echo "Bridge networking is WORKING with netlink interception!"
    else
        echo "Still failed. Checking logs..."
        tail -30 /var/log/dockerd-v2.log | grep -E "error|failed|netlink"
    fi

    echo
    echo "Netlink intercept log:"
    grep "netlink_v2" /var/log/dockerd-v2.log | tail -20
else
    echo "❌ Docker failed to start"
    tail -20 /var/log/dockerd-v2.log
fi
