#!/bin/bash
#
# Setup comprehensive fake cgroup files and bind mount them
#

set -e

FAKE_ROOT="/tmp/exp10-cgroups-complete"

echo "[INFO] Creating complete fake cgroup structure at $FAKE_ROOT..."

rm -rf "$FAKE_ROOT"
mkdir -p "$FAKE_ROOT"/{cpu,cpuacct,memory,blkio,devices,freezer,net_cls,net_prio,pids}

# CPU subsystem files
cat > "$FAKE_ROOT/cpu/cpu.shares" << EOF
1024
EOF

cat > "$FAKE_ROOT/cpu/cpu.cfs_period_us" << EOF
100000
EOF

cat > "$FAKE_ROOT/cpu/cpu.cfs_quota_us" << EOF
-1
EOF

cat > "$FAKE_ROOT/cpu/cpu.stat" << EOF
nr_periods 0
nr_throttled 0
throttled_time 0
EOF

# CPU accounting files
cat > "$FAKE_ROOT/cpuacct/cpuacct.usage" << EOF
$(date +%s%N)
EOF

cat > "$FAKE_ROOT/cpuacct/cpuacct.stat" << EOF
user 100
system 50
EOF

cat > "$FAKE_ROOT/cpuacct/cpuacct.usage_percpu" << EOF
0 0 0 0
EOF

# Memory subsystem files
cat > "$FAKE_ROOT/memory/memory.limit_in_bytes" << EOF
9223372036854771712
EOF

cat > "$FAKE_ROOT/memory/memory.usage_in_bytes" << EOF
209715200
EOF

cat > "$FAKE_ROOT/memory/memory.max_usage_in_bytes" << EOF
262144000
EOF

cat > "$FAKE_ROOT/memory/memory.stat" << EOF
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

cat > "$FAKE_ROOT/memory/memory.soft_limit_in_bytes" << EOF
9223372036854771712
EOF

# Block I/O files
touch "$FAKE_ROOT/blkio/blkio.throttle.io_service_bytes"
touch "$FAKE_ROOT/blkio/blkio.throttle.io_serviced"

# Devices
cat > "$FAKE_ROOT/devices/devices.list" << EOF
a *:* rwm
EOF

# Freezer
cat > "$FAKE_ROOT/freezer/freezer.state" << EOF
THAWED
EOF

# Network
cat > "$FAKE_ROOT/net_cls/net_cls.classid" << EOF
0
EOF

touch "$FAKE_ROOT/net_prio/net_prio.ifpriomap"

# PIDs
cat > "$FAKE_ROOT/pids/pids.max" << EOF
max
EOF

cat > "$FAKE_ROOT/pids/pids.current" << EOF
1
EOF

echo "[INFO] Files created. Testing readability..."
ls -la "$FAKE_ROOT/cpu/" | head -10
cat "$FAKE_ROOT/cpu/cpu.shares"

echo ""
echo "[INFO] Now bind-mounting over real cgroup directories..."

# Unmount any existing mounts first
umount /sys/fs/cgroup/cpu 2>/dev/null || true
umount /sys/fs/cgroup/cpuacct 2>/dev/null || true
umount /sys/fs/cgroup/memory 2>/dev/null || true

# Bind mount the populated directories
mount --bind "$FAKE_ROOT/cpu" "/sys/fs/cgroup/cpu" && echo "  ✓ Mounted /sys/fs/cgroup/cpu" || echo "  ✗ Failed to mount cpu"
mount --bind "$FAKE_ROOT/cpuacct" "/sys/fs/cgroup/cpuacct" && echo "  ✓ Mounted /sys/fs/cgroup/cpuacct" || echo "  ✗ Failed to mount cpuacct"
mount --bind "$FAKE_ROOT/memory" "/sys/fs/cgroup/memory" && echo "  ✓ Mounted /sys/fs/cgroup/memory" || echo "  ✗ Failed to mount memory"

echo ""
echo "[INFO] Verifying mounts..."
echo "Contents of /sys/fs/cgroup/cpu:"
ls -la /sys/fs/cgroup/cpu/ | head -10

echo ""
echo "Reading /sys/fs/cgroup/cpu/cpu.shares:"
cat /sys/fs/cgroup/cpu/cpu.shares 2>&1 || echo "Failed to read"

echo ""
echo "[SUCCESS] Bind mounts complete!"
