#!/bin/bash

echo "=== Testing Patched runc with Full k3s-like Config ==="
echo ""

# Setup test directory
TEST_DIR="/tmp/patched-runc-test"
rm -rf $TEST_DIR
mkdir -p $TEST_DIR/rootfs/{bin,lib/x86_64-linux-gnu,lib64}

echo "Creating rootfs..."
cp /bin/sh $TEST_DIR/rootfs/bin/
cp /bin/echo $TEST_DIR/rootfs/bin/
cp /lib/x86_64-linux-gnu/libc.so.6 $TEST_DIR/rootfs/lib/x86_64-linux-gnu/
cp /lib64/ld-linux-x86-64.so.2 $TEST_DIR/rootfs/lib64/

cd $TEST_DIR

# Create full k3s-like config WITH cgroup namespace AND capabilities
cat > config.json <<'EOF'
{
  "ociVersion": "1.0.0",
  "process": {
    "terminal": false,
    "user": {"uid": 0, "gid": 0},
    "args": ["/bin/sh", "-c", "echo 'SUCCESS: Full k3s config works with patched runc!'"],
    "env": ["PATH=/bin"],
    "cwd": "/",
    "capabilities": {
      "bounding": ["CAP_AUDIT_WRITE","CAP_KILL","CAP_NET_BIND_SERVICE"],
      "effective": ["CAP_AUDIT_WRITE","CAP_KILL","CAP_NET_BIND_SERVICE"],
      "inheritable": ["CAP_AUDIT_WRITE","CAP_KILL","CAP_NET_BIND_SERVICE"],
      "permitted": ["CAP_AUDIT_WRITE","CAP_KILL","CAP_NET_BIND_SERVICE"]
    },
    "noNewPrivileges": true
  },
  "root": {"path": "rootfs", "readonly": false},
  "mounts": [
    {"destination": "/proc", "type": "proc", "source": "proc"},
    {"destination": "/dev", "type": "tmpfs", "source": "tmpfs"}
  ],
  "linux": {
    "namespaces": [
      {"type": "pid"},
      {"type": "network"},
      {"type": "ipc"},
      {"type": "uts"},
      {"type": "mount"}
    ]
  }
}
EOF

echo "Config created (WITHOUT cgroup namespace - using wrapper)"
echo ""

# Test with patched runc + wrapper (strips cgroup)
echo "Test 1: Patched runc + wrapper (strips cgroup namespace)"
/home/user/claude-code-on-the-web/experiments/26-namespace-isolation-testing/runc-gvisor-wrapper.sh run test-patched 2>&1 | tee /tmp/patched-runc-test1.log

TEST1_STATUS=$?
/home/user/claude-code-on-the-web/experiments/27-runc-patching/runc/runc delete test-patched 2>/dev/null || true

if [ $TEST1_STATUS -eq 0 ] && grep -q "SUCCESS" /tmp/patched-runc-test1.log; then
    echo "✅ Test 1 PASSED: Wrapper + patched runc works!"
else
    echo "❌ Test 1 FAILED"
    cat /tmp/patched-runc-test1.log
fi

echo ""

# Test 2: Direct with patched runc (should also work now)
echo "Test 2: Direct patched runc (no wrapper, capabilities test)"
/home/user/claude-code-on-the-web/experiments/27-runc-patching/runc/runc run test-patched-direct 2>&1 | tee /tmp/patched-runc-test2.log

TEST2_STATUS=$?
/home/user/claude-code-on-the-web/experiments/27-runc-patching/runc/runc delete test-patched-direct 2>/dev/null || true

if [ $TEST2_STATUS -eq 0 ] && grep -q "SUCCESS" /tmp/patched-runc-test2.log; then
    echo "✅ Test 2 PASSED: Patched runc handles missing cap_last_cap!"
else
    echo "⚠️  Test 2: Check results"
    cat /tmp/patched-runc-test2.log
fi

echo ""
echo "=== Test Complete ==="
echo "Patched runc location: /home/user/claude-code-on-the-web/experiments/27-runc-patching/runc/runc"
