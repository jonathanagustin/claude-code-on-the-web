#!/bin/bash
# Cgroup Faker with inotify - Real-time cgroup file creation

CGROUP_BASE="/sys/fs/cgroup"

# Required cgroup files
CGROUP_FILES=(
    "cgroup.procs"
    "cgroup.clone_children"
    "cgroup.sane_behavior"
    "notify_on_release"
    "release_agent"
    "tasks"
    "memory.limit_in_bytes"
    "memory.soft_limit_in_bytes"
    "memory.usage_in_bytes"
    "memory.max_usage_in_bytes"
    "memory.failcnt"
    "memory.stat"
    "memory.kmem.limit_in_bytes"
    "memory.kmem.usage_in_bytes"
    "memory.oom_control"
    "cpu.cfs_period_us"
    "cpu.cfs_quota_us"
    "cpu.shares"
    "cpu.stat"
    "cpuset.cpus"
    "cpuset.mems"
)

create_cgroup_files() {
    local dir="$1"

    echo "[$(date +%T)] Creating cgroup files in: $dir"

    for file in "${CGROUP_FILES[@]}"; do
        local filepath="$dir/$file"
        if [[ ! -f "$filepath" ]]; then
            # Create file with default content
            case "$file" in
                cgroup.procs|tasks)
                    echo "" > "$filepath"
                    ;;
                *.limit_in_bytes)
                    echo "9223372036854771712" > "$filepath"  # Max int64
                    ;;
                *.usage_in_bytes|*.max_usage_in_bytes|*.failcnt)
                    echo "0" > "$filepath"
                    ;;
                memory.stat)
                    cat > "$filepath" <<EOF
cache 0
rss 0
mapped_file 0
EOF
                    ;;
                memory.oom_control)
                    echo "0" > "$filepath"
                    ;;
                cpu.cfs_period_us)
                    echo "100000" > "$filepath"
                    ;;
                cpu.cfs_quota_us)
                    echo "-1" > "$filepath"
                    ;;
                cpu.shares)
                    echo "1024" > "$filepath"
                    ;;
                cpu.stat)
                    echo "0" > "$filepath"
                    ;;
                cpuset.cpus)
                    echo "0-3" > "$filepath"
                    ;;
                cpuset.mems)
                    echo "0" > "$filepath"
                    ;;
                *)
                    echo "0" > "$filepath"
                    ;;
            esac
            chmod 666 "$filepath" 2>/dev/null || true
        fi
    done
    echo "[$(date +%T)] ✅ Completed cgroup files for: $dir"
}

echo "=========================================="
echo "Starting inotify-based cgroup faker daemon"
echo "=========================================="

# Initial population of existing directories
echo "[$(date +%T)] Populating existing directories..."
for subsystem in memory cpu cpuacct cpuset blkio devices freezer net_cls perf_event net_prio hugetlb pids rdma misc; do
    basedir="$CGROUP_BASE/$subsystem/k8s.io"
    if [[ -d "$basedir" ]]; then
        create_cgroup_files "$basedir"
        # Populate existing subdirectories
        find "$basedir" -mindepth 1 -type d 2>/dev/null | while read -r dir; do
            create_cgroup_files "$dir"
        done
    fi
done

echo "[$(date +%T)] Initial population complete. Starting real-time monitoring..."

# Real-time monitoring with inotify
for subsystem in memory cpu cpuacct cpuset blkio devices freezer net_cls perf_event net_prio hugetlb pids rdma misc; do
    basedir="$CGROUP_BASE/$subsystem/k8s.io"
    if [[ -d "$basedir" ]]; then
        (
            echo "[$(date +%T)] 🔍 Watching: $basedir"
            inotifywait -m -e create --format '%w%f' "$basedir" 2>/dev/null | while read -r newdir; do
                if [[ -d "$newdir" ]]; then
                    echo "[$(date +%T)] 🚨 NEW DIRECTORY DETECTED: $newdir"
                    create_cgroup_files "$newdir"
                fi
            done
        ) &
    fi
done

echo "[$(date +%T)] ✅ All inotify watchers started. Monitoring for new cgroup directories..."
echo "=========================================="

# Keep script running
wait
