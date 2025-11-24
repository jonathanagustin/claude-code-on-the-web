#!/bin/bash

echo "=== Experiment 25: Direct runc Testing (Minimal Rootfs) ==="
echo ""
echo "Testing if runc can execute containers in gVisor environment"
echo "Using minimal busybox rootfs"
echo ""

# Create test directory
TEST_DIR="/tmp/runc-minimal-test"
rm -rf $TEST_DIR
mkdir -p $TEST_DIR/rootfs/{bin,proc,dev}

echo "Step 1: Creating minimal rootfs with busybox..."

# Check if busybox is available
if ! command -v busybox &> /dev/null; then
    echo "✗ busybox not found, cannot create minimal rootfs"
    echo "Trying alternative: using /bin/sh directly"

    # Copy essential binaries
    mkdir -p $TEST_DIR/rootfs/bin
    cp /bin/sh $TEST_DIR/rootfs/bin/ 2>/dev/null || cp /bin/bash $TEST_DIR/rootfs/bin/sh
    cp /bin/echo $TEST_DIR/rootfs/bin/ 2>/dev/null || true

    # Copy required libraries
    mkdir -p $TEST_DIR/rootfs/lib $TEST_DIR/rootfs/lib64

    # Get library dependencies for sh
    for lib in $(ldd /bin/sh 2>/dev/null | grep -o '/lib[^ ]*' | sort -u); do
        if [ -f "$lib" ]; then
            cp "$lib" $TEST_DIR/rootfs/$lib 2>/dev/null || true
        fi
    done

    # Get library dependencies for echo if it exists
    if [ -f /bin/echo ]; then
        for lib in $(ldd /bin/echo 2>/dev/null | grep -o '/lib[^ ]*' | sort -u); do
            if [ -f "$lib" ]; then
                cp "$lib" $TEST_DIR/rootfs/$lib 2>/dev/null || true
            fi
        done
    fi
else
    # Use busybox to create a minimal filesystem
    cp $(which busybox) $TEST_DIR/rootfs/bin/

    # Create symlinks for common commands
    cd $TEST_DIR/rootfs/bin
    for cmd in sh echo ls cat; do
        ln -s busybox $cmd 2>/dev/null || true
    done
    cd -
fi

echo "✓ Minimal rootfs created ($(du -sh $TEST_DIR/rootfs | cut -f1))"
ls -la $TEST_DIR/rootfs/bin/
echo ""

# Change to test directory
cd $TEST_DIR

echo "Step 2: Creating minimal OCI config..."
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
      "/bin/sh",
      "-c",
      "echo 'SUCCESS: runc container executed in gVisor!'"
    ],
    "env": [
      "PATH=/bin"
    ],
    "cwd": "/"
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
      "options": ["nosuid","strictatime","mode=755"]
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

echo "✓ OCI config created"
echo ""

echo "Step 3: Attempting to run container with runc..."
echo "Command: runc run test-minimal"
echo "---"

# Apply fake proc/sys workaround
mkdir -p /tmp/fake-procsys/kernel
echo "40" > /tmp/fake-procsys/kernel/cap_last_cap

# Try with LD_PRELOAD if available
if [ -f /tmp/runc-preload.so ]; then
    echo "(Using LD_PRELOAD wrapper)"
    LD_PRELOAD=/tmp/runc-preload.so runc run test-minimal 2>&1 | tee /tmp/runc-minimal.log
    RUN_STATUS=${PIPESTATUS[0]}
else
    runc run test-minimal 2>&1 | tee /tmp/runc-minimal.log
    RUN_STATUS=${PIPESTATUS[0]}
fi

echo "---"
echo ""

if [ $RUN_STATUS -eq 0 ] && grep -q "SUCCESS" /tmp/runc-minimal.log; then
    echo "✅ SUCCESS: runc container executed successfully!"
    echo ""
    echo "🎉 BREAKTHROUGH: Containers CAN run in gVisor outside k3s!"
    echo ""
    echo "This means:"
    echo "  • The blocker is k3s/containerd configuration specific"
    echo "  • NOT a fundamental gVisor limitation"
    echo "  • We can configure k3s to use this working approach"
    echo ""
    echo "Next steps:"
    echo "  1. Analyze what's different in our config vs k3s config"
    echo "  2. Apply these settings to k3s containerd configuration"
    echo "  3. Test pod execution with updated config"
else
    echo "❌ FAILED: runc container execution failed"
    echo ""
    echo "Exit code: $RUN_STATUS"
    echo ""
    echo "Analyzing error..."

    if grep -q "cap_last_cap" /tmp/runc-minimal.log; then
        echo "⚠️  Error: cap_last_cap missing"
        echo "   This confirms it's a fundamental gVisor limitation"
        echo "   Same blocker as k3s pods"
    elif grep -q "session keyring" /tmp/runc-minimal.log; then
        echo "⚠️  Error: session keyring issue"
        echo "   This confirms it's a fundamental gVisor limitation"
        echo "   Same blocker as k3s pods"
    elif grep -q "cgroup" /tmp/runc-minimal.log; then
        echo "⚠️  Error: cgroup related"
        echo "   May be related to missing cgroup files in gVisor"
    else
        echo "Different error - full log:"
        cat /tmp/runc-minimal.log
    fi
fi

echo ""
echo "=== Cleanup ==="
runc delete test-minimal 2>/dev/null || true
cd /home/user/claude-code-on-the-web
# Keep test directory for inspection: rm -rf $TEST_DIR

echo "✓ Container deleted"
echo ""
echo "=== Test Complete ==="
echo ""
echo "Test directory preserved at: $TEST_DIR"
echo "Logs saved to: /tmp/runc-minimal.log"
