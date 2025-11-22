#!/bin/bash
#
# Setup fake cgroup files for LD_PRELOAD redirection
#

set -e

FAKE_CGROUP="/tmp/fake-cgroup"
FAKE_PROCSYS="/tmp/fake-procsys"

echo "[INFO] Creating fake cgroup filesystem at $FAKE_CGROUP"

# Create cgroup subsystem directories
mkdir -p "$FAKE_CGROUP"/{cpu,cpuacct,memory,blkio,devices,freezer,net_cls,net_prio,pids}

# CPU subsystem
cat > "$FAKE_CGROUP/cpu/cpu.shares" << EOF
1024
EOF

cat > "$FAKE_CGROUP/cpu/cpu.cfs_period_us" << EOF
100000
EOF

cat > "$FAKE_CGROUP/cpu/cpu.cfs_quota_us" << EOF
-1
EOF

cat > "$FAKE_CGROUP/cpu/cpu.stat" << EOF
nr_periods 0
nr_throttled 0
throttled_time 0
EOF

# CPU accounting
cat > "$FAKE_CGROUP/cpuacct/cpuacct.usage" << EOF
$(date +%s%N)
EOF

cat > "$FAKE_CGROUP/cpuacct/cpuacct.stat" << EOF
user 100
system 50
EOF

# Memory
cat > "$FAKE_CGROUP/memory/memory.limit_in_bytes" << EOF
9223372036854771712
EOF

cat > "$FAKE_CGROUP/memory/memory.usage_in_bytes" << EOF
209715200
EOF

cat > "$FAKE_CGROUP/memory/memory.max_usage_in_bytes" << EOF
262144000
EOF

cat > "$FAKE_CGROUP/memory/memory.stat" << EOF
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

# Block I/O
touch "$FAKE_CGROUP/blkio/blkio.throttle.io_service_bytes"
touch "$FAKE_CGROUP/blkio/blkio.throttle.io_serviced"

# Devices
cat > "$FAKE_CGROUP/devices/devices.list" << EOF
a *:* rwm
EOF

# Freezer
cat > "$FAKE_CGROUP/freezer/freezer.state" << EOF
THAWED
EOF

# Network
cat > "$FAKE_CGROUP/net_cls/net_cls.classid" << EOF
0
EOF

touch "$FAKE_CGROUP/net_prio/net_prio.ifpriomap"

# PIDs
cat > "$FAKE_CGROUP/pids/pids.max" << EOF
max
EOF

cat > "$FAKE_CGROUP/pids/pids.current" << EOF
1
EOF

echo "[INFO] Creating fake /proc/sys files at $FAKE_PROCSYS"

# Create /proc/sys files (from Experiment 04)
mkdir -p "$FAKE_PROCSYS/kernel"
mkdir -p "$FAKE_PROCSYS/vm"
mkdir -p "$FAKE_PROCSYS/net/core"
mkdir -p "$FAKE_PROCSYS/net/ipv4"

# Kernel parameters
echo "0" > "$FAKE_PROCSYS/kernel/panic"
echo "0" > "$FAKE_PROCSYS/kernel/panic_on_oops"
echo "65536" > "$FAKE_PROCSYS/kernel/pid_max"
echo "262144" > "$FAKE_PROCSYS/kernel/threads-max"

# VM parameters
echo "0" > "$FAKE_PROCSYS/vm/overcommit_memory"
echo "50" > "$FAKE_PROCSYS/vm/panic_on_oom"

# Network parameters
echo "212992" > "$FAKE_PROCSYS/net/core/rmem_max"
echo "212992" > "$FAKE_PROCSYS/net/core/wmem_max"
echo "1" > "$FAKE_PROCSYS/net/ipv4/ip_forward"

echo "[INFO] Fake filesystem setup complete"
echo "[INFO] Use with: LD_PRELOAD=./ld_preload_interceptor.so k3s server [args]"
