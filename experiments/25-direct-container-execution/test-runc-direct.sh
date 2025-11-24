#!/bin/bash

echo "=== Experiment 25: Direct runc Testing ==="
echo ""
echo "Testing if runc can execute containers in gVisor environment"
echo "Using pre-existing k3s image to avoid network pulls"
echo ""

# Create test directory
TEST_DIR="/tmp/runc-direct-test"
rm -rf $TEST_DIR
mkdir -p $TEST_DIR/rootfs

echo "Step 1: Creating container rootfs from existing image..."
# Export rootfs from existing k3s image
CONTAINER_ID=$(podman create rancher/k3s:latest /bin/sh)
if [ -z "$CONTAINER_ID" ]; then
    echo "✗ Failed to create container from existing image"
    exit 1
fi

podman export $CONTAINER_ID | tar -C $TEST_DIR/rootfs -xf -
podman rm $CONTAINER_ID > /dev/null 2>&1

echo "✓ Rootfs created ($(du -sh $TEST_DIR/rootfs | cut -f1))"
echo ""

# Change to test directory
cd $TEST_DIR

echo "Step 2: Generating runc config.json..."
runc spec

echo "✓ Config generated"
echo ""

echo "Step 3: Modifying config for simple test..."
# Create a simple config that just echoes
cat > config.json <<'EOF'
{
  "ociVersion": "1.0.0",
  "process": {
    "terminal": false,
    "user": {
      "uid": 0,
      "gid": 0
    },
    "args": [
      "/bin/echo",
      "SUCCESS: Container executed in gVisor!"
    ],
    "env": [
      "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    ],
    "cwd": "/",
    "capabilities": {
      "bounding": ["CAP_AUDIT_WRITE","CAP_KILL","CAP_NET_BIND_SERVICE"],
      "effective": ["CAP_AUDIT_WRITE","CAP_KILL","CAP_NET_BIND_SERVICE"],
      "inheritable": ["CAP_AUDIT_WRITE","CAP_KILL","CAP_NET_BIND_SERVICE"],
      "permitted": ["CAP_AUDIT_WRITE","CAP_KILL","CAP_NET_BIND_SERVICE"]
    },
    "noNewPrivileges": true
  },
  "root": {
    "path": "rootfs",
    "readonly": false
  },
  "hostname": "runc-test",
  "mounts": [
    {
      "destination": "/proc",
      "type": "proc",
      "source": "proc"
    },
    {
      "destination": "/dev",
      "type": "tmpfs",
      "source": "tmpfs",
      "options": ["nosuid","strictatime","mode=755","size=65536k"]
    }
  ],
  "linux": {
    "namespaces": [
      {"type": "pid"},
      {"type": "ipc"},
      {"type": "uts"},
      {"type": "mount"}
    ]
  }
}
EOF

echo "✓ Config modified for non-interactive execution"
echo ""

echo "Step 4: Attempting to run container with runc..."
echo "---"
runc run test-container-25 2>&1 | tee /tmp/runc-direct.log
RUN_STATUS=${PIPESTATUS[0]}
echo "---"
echo ""

if [ $RUN_STATUS -eq 0 ]; then
    echo "✅ SUCCESS: runc container executed successfully!"
    echo ""
    echo "This means the blocker is k3s/containerd specific, NOT a fundamental gVisor limitation!"
else
    echo "❌ FAILED: runc container execution failed"
    echo ""
    echo "Analyzing error..."

    if grep -q "cap_last_cap" /tmp/runc-direct.log; then
        echo "⚠️  Error: cap_last_cap missing - SAME as k3s blocker"
        echo "   This is a fundamental gVisor limitation affecting ALL runc usage"
    elif grep -q "session keyring" /tmp/runc-direct.log; then
        echo "⚠️  Error: session keyring - SAME as k3s blocker"
        echo "   This is a fundamental gVisor limitation affecting ALL runc usage"
    elif grep -q "no such device" /tmp/runc-direct.log; then
        echo "⚠️  Error: /dev/tty missing - configuration issue, not fundamental"
        echo "   This can be worked around with terminal: false"
    else
        echo "Different error from k3s - review log:"
        cat /tmp/runc-direct.log
    fi
fi

echo ""
echo "=== Cleanup ==="
# Try to delete container if it exists
runc delete test-container-25 2>/dev/null || true
cd /home/user/claude-code-on-the-web
rm -rf $TEST_DIR

echo ""
echo "=== Test Complete ==="
echo ""
echo "Logs saved to: /tmp/runc-direct.log"
