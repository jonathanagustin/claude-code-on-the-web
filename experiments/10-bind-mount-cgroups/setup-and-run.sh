#!/bin/bash
#
# Experiment 10: Direct Bind Mount Approach
# Mount fake cgroup files directly to /sys/fs/cgroup
#

set -e

echo "========================================="
echo "Experiment 10: Direct Bind Mount Cgroups"
echo "========================================="
echo ""
echo "Strategy: Mount fake cgroup files directly over real paths"
echo "  - Create fake cgroup files with proper structure"
echo "  - Bind mount them to /sys/fs/cgroup/<subsystem>/*"
echo "  - No kernel/ptrace/LD_PRELOAD needed!"
echo ""

# Create fake cgroup files
FAKE_ROOT="/tmp/exp10-fake-cgroups"
mkdir -p "$FAKE_ROOT"

echo "[INFO] Creating fake cgroup directory structure..."

# Create subsystem directories
for subsys in cpu cpuacct memory blkio devices freezer net_cls net_prio pids; do
    mkdir -p "$FAKE_ROOT/$subsys"
    mkdir -p "/sys/fs/cgroup/$subsys" 2>/dev/null || true
done

# Create individual cgroup files with content
cat > "$FAKE_ROOT/cpu_shares" << EOF
1024
EOF

cat > "$FAKE_ROOT/cpu_cfs_period_us" << EOF
100000
EOF

cat > "$FAKE_ROOT/cpu_cfs_quota_us" << EOF
-1
EOF

cat > "$FAKE_ROOT/cpu_stat" << EOF
nr_periods 0
nr_throttled 0
throttled_time 0
EOF

cat > "$FAKE_ROOT/cpuacct_usage" << EOF
$(date +%s%N)
EOF

cat > "$FAKE_ROOT/cpuacct_stat" << EOF
user 100
system 50
EOF

cat > "$FAKE_ROOT/memory_limit_in_bytes" << EOF
9223372036854771712
EOF

cat > "$FAKE_ROOT/memory_usage_in_bytes" << EOF
209715200
EOF

cat > "$FAKE_ROOT/memory_stat" << EOF
cache 0
rss 209715200
rss_huge 0
mapped_file 0
swap 0
pgpgin 0
pgpgout 0
pgfault 0
pgmajfault 0
inactive_anon 0
active_anon 209715200
inactive_file 0
active_file 0
unevictable 0
EOF

cat > "$FAKE_ROOT/devices_list" << EOF
a *:* rwm
EOF

cat > "$FAKE_ROOT/freezer_state" << EOF
THAWED
EOF

touch "$FAKE_ROOT/blkio_io_service_bytes"
touch "$FAKE_ROOT/net_cls_classid"
touch "$FAKE_ROOT/pids_max"

echo "[INFO] Attempting bind mounts..."

# Try to bind mount individual files
# This might fail in gVisor, but let's try
mount --bind "$FAKE_ROOT/cpu_shares" "/sys/fs/cgroup/cpu/cpu.shares" 2>/dev/null && echo "  ✓ cpu.shares" || echo "  ✗ cpu.shares (expected - may need different approach)"
mount --bind "$FAKE_ROOT/memory_limit_in_bytes" "/sys/fs/cgroup/memory/memory.limit_in_bytes" 2>/dev/null && echo "  ✓ memory.limit_in_bytes" || echo "  ✗ memory.limit_in_bytes"

echo ""
echo "[INFO] Checking if any mounts succeeded..."
mount | grep "$FAKE_ROOT" || echo "  No bind mounts active"

echo ""
echo "[INFO] Alternative: Try mounting entire subsystem directories..."

# Alternative: Mount entire directories
for subsys in cpu cpuacct memory; do
    if [ -d "/sys/fs/cgroup/$subsys" ]; then
        mount --bind "$FAKE_ROOT/$subsys" "/sys/fs/cgroup/$subsys" 2>/dev/null && echo "  ✓ $subsys directory" || echo "  ✗ $subsys directory"
    fi
done

echo ""
echo "[INFO] Final mount check..."
mount | grep -E "(cgroup|$FAKE_ROOT)" | head -10 || echo "  No cgroup-related mounts found"

echo ""
echo "========================================="
echo "Experiment 10 Result"
echo "========================================="
echo ""
echo "This experiment tests whether we can use bind mounts"
echo "to replace cgroup files in gVisor. If gVisor restricts"
echo "mount operations, we'll see failures above."
echo ""
