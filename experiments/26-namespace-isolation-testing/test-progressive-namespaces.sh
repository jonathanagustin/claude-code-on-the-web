#!/bin/bash

echo "=== Experiment 26: Progressive Namespace Isolation Testing ==="
echo ""
echo "Goal: Identify which namespace or configuration triggers cap_last_cap blocker"
echo "Method: Add namespaces incrementally until container execution fails"
echo ""

# Prepare test environment
RESULTS_FILE="/tmp/namespace-test-results.txt"
> $RESULTS_FILE

# Create base rootfs (reuse from Experiment 25)
BASE_DIR="/tmp/namespace-tests"
rm -rf $BASE_DIR
mkdir -p $BASE_DIR

echo "Setting up base rootfs..."
mkdir -p $BASE_DIR/rootfs/{bin,lib/x86_64-linux-gnu,lib64,proc,dev}
cp /bin/sh $BASE_DIR/rootfs/bin/
cp /bin/echo $BASE_DIR/rootfs/bin/
cp /lib/x86_64-linux-gnu/libc.so.6 $BASE_DIR/rootfs/lib/x86_64-linux-gnu/
cp /lib64/ld-linux-x86-64.so.2 $BASE_DIR/rootfs/lib64/
echo "✓ Base rootfs ready"
echo ""

# Ensure fake /proc/sys files exist for LD_PRELOAD
mkdir -p /tmp/fake-procsys/kernel
echo "40" > /tmp/fake-procsys/kernel/cap_last_cap

# Test function
run_test() {
    local test_name=$1
    local config_file=$2
    local test_num=$3

    echo "=== Test $test_num: $test_name ==="

    cd $BASE_DIR
    cp $config_file config.json

    # Try with LD_PRELOAD wrapper if available
    if [ -f /tmp/runc-preload.so ]; then
        LD_PRELOAD=/tmp/runc-preload.so timeout 10 runc run test-ns-$test_num > /tmp/test-$test_num.log 2>&1
        STATUS=$?
    else
        timeout 10 runc run test-ns-$test_num > /tmp/test-$test_num.log 2>&1
        STATUS=$?
    fi

    # Cleanup
    runc delete test-ns-$test_num 2>/dev/null || true

    if [ $STATUS -eq 0 ] && grep -q "SUCCESS" /tmp/test-$test_num.log; then
        echo "✅ PASS: $test_name"
        echo "PASS: $test_name" >> $RESULTS_FILE
        return 0
    else
        echo "❌ FAIL: $test_name"
        echo "FAIL: $test_name" >> $RESULTS_FILE

        # Analyze failure
        if grep -q "cap_last_cap" /tmp/test-$test_num.log; then
            echo "   Blocker: cap_last_cap error"
            echo "   -> This configuration requires cap_last_cap!" | tee -a $RESULTS_FILE
        elif grep -q "session keyring" /tmp/test-$test_num.log; then
            echo "   Blocker: session keyring error"
            echo "   -> This configuration requires session keyring!" | tee -a $RESULTS_FILE
        elif grep -q "cgroup" /tmp/test-$test_num.log; then
            echo "   Blocker: cgroup error"
            echo "   -> This configuration requires cgroup files!" | tee -a $RESULTS_FILE
        else
            echo "   Error: $(head -3 /tmp/test-$test_num.log | tail -1)"
        fi

        return 1
    fi
    echo ""
}

# Test 1: Minimal (baseline from Experiment 25)
cat > $BASE_DIR/config-test1.json <<'EOF'
{
  "ociVersion": "1.0.0",
  "process": {
    "terminal": false,
    "user": {"uid": 0, "gid": 0},
    "args": ["/bin/sh", "-c", "echo 'SUCCESS: Minimal namespaces'"],
    "env": ["PATH=/bin"],
    "cwd": "/"
  },
  "root": {"path": "rootfs", "readonly": false},
  "mounts": [
    {"destination": "/proc", "type": "proc", "source": "proc"},
    {"destination": "/dev", "type": "tmpfs", "source": "tmpfs"}
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

run_test "Minimal (pid, ipc, uts, mount)" "$BASE_DIR/config-test1.json" 1

# Test 2: Add network namespace
cat > $BASE_DIR/config-test2.json <<'EOF'
{
  "ociVersion": "1.0.0",
  "process": {
    "terminal": false,
    "user": {"uid": 0, "gid": 0},
    "args": ["/bin/sh", "-c", "echo 'SUCCESS: With network namespace'"],
    "env": ["PATH=/bin"],
    "cwd": "/"
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

run_test "Add network namespace" "$BASE_DIR/config-test2.json" 2

# Test 3: Add user namespace
cat > $BASE_DIR/config-test3.json <<'EOF'
{
  "ociVersion": "1.0.0",
  "process": {
    "terminal": false,
    "user": {"uid": 0, "gid": 0},
    "args": ["/bin/sh", "-c", "echo 'SUCCESS: With user namespace'"],
    "env": ["PATH=/bin"],
    "cwd": "/"
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
      {"type": "mount"},
      {"type": "user"}
    ],
    "uidMappings": [{"containerID": 0, "hostID": 0, "size": 1}],
    "gidMappings": [{"containerID": 0, "hostID": 0, "size": 1}]
  }
}
EOF

run_test "Add user namespace" "$BASE_DIR/config-test3.json" 3

# Test 4: Add cgroup namespace (SUSPECTED BLOCKER)
cat > $BASE_DIR/config-test4.json <<'EOF'
{
  "ociVersion": "1.0.0",
  "process": {
    "terminal": false,
    "user": {"uid": 0, "gid": 0},
    "args": ["/bin/sh", "-c", "echo 'SUCCESS: With cgroup namespace'"],
    "env": ["PATH=/bin"],
    "cwd": "/"
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
      {"type": "mount"},
      {"type": "cgroup"}
    ]
  }
}
EOF

run_test "Add cgroup namespace" "$BASE_DIR/config-test4.json" 4

# Test 5: Add capabilities configuration (SUSPECTED TRIGGER)
cat > $BASE_DIR/config-test5.json <<'EOF'
{
  "ociVersion": "1.0.0",
  "process": {
    "terminal": false,
    "user": {"uid": 0, "gid": 0},
    "args": ["/bin/sh", "-c", "echo 'SUCCESS: With capabilities'"],
    "env": ["PATH=/bin"],
    "cwd": "/",
    "capabilities": {
      "bounding": ["CAP_AUDIT_WRITE","CAP_KILL","CAP_NET_BIND_SERVICE"],
      "effective": ["CAP_AUDIT_WRITE","CAP_KILL","CAP_NET_BIND_SERVICE"],
      "inheritable": ["CAP_AUDIT_WRITE","CAP_KILL","CAP_NET_BIND_SERVICE"],
      "permitted": ["CAP_AUDIT_WRITE","CAP_KILL","CAP_NET_BIND_SERVICE"],
      "ambient": ["CAP_AUDIT_WRITE","CAP_KILL","CAP_NET_BIND_SERVICE"]
    }
  },
  "root": {"path": "rootfs", "readonly": false},
  "mounts": [
    {"destination": "/proc", "type": "proc", "source": "proc"},
    {"destination": "/dev", "type": "tmpfs", "source": "tmpfs"}
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

run_test "Add capabilities config" "$BASE_DIR/config-test5.json" 5

# Test 6: Full k3s-like configuration
cat > $BASE_DIR/config-test6.json <<'EOF'
{
  "ociVersion": "1.0.0",
  "process": {
    "terminal": false,
    "user": {"uid": 0, "gid": 0},
    "args": ["/bin/sh", "-c", "echo 'SUCCESS: Full k3s config'"],
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
    {"destination": "/dev", "type": "tmpfs", "source": "tmpfs"},
    {"destination": "/sys", "type": "sysfs", "source": "sysfs", "options": ["nosuid","noexec","nodev","ro"]}
  ],
  "linux": {
    "namespaces": [
      {"type": "pid"},
      {"type": "network"},
      {"type": "ipc"},
      {"type": "uts"},
      {"type": "mount"},
      {"type": "cgroup"}
    ],
    "resources": {
      "devices": [{"allow": false, "access": "rwm"}]
    },
    "cgroupsPath": "/test-cgroup"
  }
}
EOF

run_test "Full k3s-like config" "$BASE_DIR/config-test6.json" 6

# Test 7: Capabilities with cgroup namespace
cat > $BASE_DIR/config-test7.json <<'EOF'
{
  "ociVersion": "1.0.0",
  "process": {
    "terminal": false,
    "user": {"uid": 0, "gid": 0},
    "args": ["/bin/sh", "-c", "echo 'SUCCESS: Capabilities + cgroup namespace'"],
    "env": ["PATH=/bin"],
    "cwd": "/",
    "capabilities": {
      "bounding": ["CAP_AUDIT_WRITE","CAP_KILL","CAP_NET_BIND_SERVICE"],
      "effective": ["CAP_AUDIT_WRITE","CAP_KILL","CAP_NET_BIND_SERVICE"],
      "inheritable": ["CAP_AUDIT_WRITE","CAP_KILL","CAP_NET_BIND_SERVICE"],
      "permitted": ["CAP_AUDIT_WRITE","CAP_KILL","CAP_NET_BIND_SERVICE"]
    }
  },
  "root": {"path": "rootfs", "readonly": false},
  "mounts": [
    {"destination": "/proc", "type": "proc", "source": "proc"},
    {"destination": "/dev", "type": "tmpfs", "source": "tmpfs"}
  ],
  "linux": {
    "namespaces": [
      {"type": "pid"},
      {"type": "ipc"},
      {"type": "uts"},
      {"type": "mount"},
      {"type": "cgroup"}
    ]
  }
}
EOF

run_test "Capabilities + cgroup ns" "$BASE_DIR/config-test7.json" 7

echo ""
echo "=== Test Results Summary ==="
echo ""
cat $RESULTS_FILE
echo ""

# Analyze results
echo "=== Analysis ==="
PASS_COUNT=$(grep -c "^PASS:" $RESULTS_FILE)
FAIL_COUNT=$(grep -c "^FAIL:" $RESULTS_FILE)

echo "Tests passed: $PASS_COUNT/7"
echo "Tests failed: $FAIL_COUNT/7"
echo ""

if [ $FAIL_COUNT -gt 0 ]; then
    echo "First failure at:"
    FIRST_FAIL=$(grep -n "^FAIL:" $RESULTS_FILE | head -1 | cut -d: -f2)
    echo "  $FIRST_FAIL"
    echo ""

    # Check for specific blocker patterns
    if grep -q "cap_last_cap" $RESULTS_FILE; then
        echo "🎯 Root cause: cap_last_cap requirement triggered"
        echo "   Likely triggered by: capabilities configuration or cgroup namespace"
    elif grep -q "cgroup" $RESULTS_FILE; then
        echo "🎯 Root cause: cgroup files requirement"
        echo "   Likely triggered by: cgroup namespace or cgroupsPath"
    fi
fi

echo ""
echo "=== Next Steps ==="
echo ""
echo "Based on results, we should:"
echo "1. Focus on configuration that caused first failure"
echo "2. Test if removing that specific setting allows execution"
echo "3. Create minimal runc patch to bypass the blocker"
echo ""
echo "Test logs preserved in: /tmp/test-*.log"
echo "Results file: $RESULTS_FILE"
echo "Test directory: $BASE_DIR (preserved for inspection)"
