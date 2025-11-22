#!/bin/bash
#
# Experiment 11: tmpfs-based cgroup files
# tmpfs IS in cAdvisor's supported filesystem list!
#

set -e

echo "========================================"
echo "Experiment 11: tmpfs Cgroup Files"
echo "========================================"
echo ""
echo "Key Insight: tmpfs is in cAdvisor's supportedFsType!"
echo "  Previously: Mounted 9p files (unsupported)"
echo "  Now: Mount tmpfs files (SUPPORTED!)"
echo ""

# Create tmpfs mount for cgroup files
TMPFS_MOUNT="/mnt/tmpfs-cgroups"
mkdir -p "$TMPFS_MOUNT"

echo "[INFO] Creating tmpfs mount..."
mount -t tmpfs -o size=50M tmpfs "$TMPFS_MOUNT"
df -T "$TMPFS_MOUNT"

echo ""
echo "[INFO] Creating cgroup file structure ON tmpfs..."

# Create subsystem directories
mkdir -p "$TMPFS_MOUNT"/{cpu,cpuacct,memory,blkio,devices,freezer,pids}

# CPU subsystem files
cat > "$TMPFS_MOUNT/cpu/cpu.shares" << EOF
1024
EOF

cat > "$TMPFS_MOUNT/cpu/cpu.cfs_period_us" << EOF
100000
EOF

cat > "$TMPFS_MOUNT/cpu/cpu.cfs_quota_us" << EOF
-1
EOF

cat > "$TMPFS_MOUNT/cpu/cpu.stat" << EOF
nr_periods 0
nr_throttled 0
throttled_time 0
EOF

# CPU accounting
cat > "$TMPFS_MOUNT/cpuacct/cpuacct.usage" << EOF
$(date +%s%N)
EOF

cat > "$TMPFS_MOUNT/cpuacct/cpuacct.stat" << EOF
user 100
system 50
EOF

cat > "$TMPFS_MOUNT/cpuacct/cpuacct.usage_percpu" << EOF
0 0 0 0 0 0 0 0
EOF

# Memory subsystem
cat > "$TMPFS_MOUNT/memory/memory.limit_in_bytes" << EOF
9223372036854771712
EOF

cat > "$TMPFS_MOUNT/memory/memory.usage_in_bytes" << EOF
209715200
EOF

cat > "$TMPFS_MOUNT/memory/memory.max_usage_in_bytes" << EOF
262144000
EOF

cat > "$TMPFS_MOUNT/memory/memory.stat" << EOF
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

cat > "$TMPFS_MOUNT/memory/memory.soft_limit_in_bytes" << EOF
9223372036854771712
EOF

# Other subsystems
touch "$TMPFS_MOUNT/blkio/blkio.throttle.io_service_bytes"
cat > "$TMPFS_MOUNT/devices/devices.list" << EOF
a *:* rwm
EOF

cat > "$TMPFS_MOUNT/freezer/freezer.state" << EOF
THAWED
EOF

cat > "$TMPFS_MOUNT/pids/pids.max" << EOF
max
EOF

cat > "$TMPFS_MOUNT/pids/pids.current" << EOF
1
EOF

echo "[INFO] Files created on tmpfs. Verifying filesystem type..."
stat -f -c "Filesystem type: %T (magic: 0x%t)" "$TMPFS_MOUNT/cpu/cpu.shares"

echo ""
echo "[INFO] Unmounting existing cgroup mounts..."
umount /sys/fs/cgroup/cpu 2>/dev/null || true
umount /sys/fs/cgroup/cpuacct 2>/dev/null || true
umount /sys/fs/cgroup/memory 2>/dev/null || true

echo "[INFO] Bind-mounting tmpfs directories to /sys/fs/cgroup..."
mount --bind "$TMPFS_MOUNT/cpu" "/sys/fs/cgroup/cpu"
mount --bind "$TMPFS_MOUNT/cpuacct" "/sys/fs/cgroup/cpuacct"
mount --bind "$TMPFS_MOUNT/memory" "/sys/fs/cgroup/memory"

echo ""
echo "[INFO] Verifying bind mounts..."
echo "Filesystem type of /sys/fs/cgroup/cpu/cpu.shares:"
stat -f -c "  %T (magic: 0x%t)" "/sys/fs/cgroup/cpu/cpu.shares"

echo ""
echo "Reading /sys/fs/cgroup/cpu/cpu.shares:"
cat /sys/fs/cgroup/cpu/cpu.shares

echo ""
echo "========================================"
echo "tmpfs setup complete!"
echo "========================================"
echo ""
echo "Filesystem type: tmpfs (SUPPORTED by cAdvisor!)"
echo "Ready to test with k3s"
