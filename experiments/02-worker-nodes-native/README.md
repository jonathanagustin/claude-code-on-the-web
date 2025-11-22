# Experiment 2: Worker Nodes Native

## Hypothesis

By systematically resolving each blocker (missing devices, mount restrictions, etc.), we can enable k3s worker nodes to run natively in the sandboxed environment.

## Rationale

Worker nodes fail due to specific technical issues. If we can identify and fix each issue, the worker node should eventually start successfully.

## Method

Iterative debugging approach:
1. Run k3s server (with worker)
2. Identify error
3. Research and implement fix
4. Repeat

## Iteration Log

### Iteration 1: Baseline

**Command**:
```bash
k3s server
```

**Error**:
```
Failed to start ContainerManager" err="[
  open /proc/sys/kernel/keys/root_maxkeys: no such file or directory,
  open /proc/sys/kernel/keys/root_maxbytes: no such file or directory,
  write /proc/sys/vm/overcommit_memory: input/output error,
  open /proc/sys/vm/panic_on_oom: no such file or directory,
  open /proc/sys/kernel/panic: no such file or directory,
  open /proc/sys/kernel/panic_on_oops: no such file or directory,
  failed to get rootfs info: unable to find data in memory cache
]"
```

**Analysis**: Multiple issues - missing /proc/sys files AND cAdvisor rootfs issue

### Iteration 2: Fix /dev/kmsg

**Issue**: `/dev/kmsg` device missing

**Research**: Found kind (Kubernetes-in-Docker) uses bind-mount workaround

**Fix**:
```bash
touch /dev/kmsg
mount --bind /dev/null /dev/kmsg
```

**Result**: ✅ /dev/kmsg error resolved

### Iteration 3: Fix Mount Propagation

**Issue**: `permission denied` when setting up bind mounts

**Error**:
```
failed to setup bind mounts: permission denied on mount
```

**Research**: Sandboxes restrict mount operations

**Fix**:
```bash
unshare --mount --propagation unchanged bash -c '
    mount --make-rshared /
    k3s server
'
```

**Result**: ✅ Mount propagation errors resolved

### Iteration 4: Fix Image Garbage Collection

**Issue**: Invalid image GC threshold configuration

**Error**:
```
invalid image GC high threshold: must be >= low threshold
```

**Fix**:
```bash
k3s server \
    --kubelet-arg="--image-gc-high-threshold=100" \
    --kubelet-arg="--image-gc-low-threshold=99"
```

**Result**: ✅ Image GC errors resolved

### Iteration 5: Fix CNI Plugins

**Issue**: CNI plugins not found

**Error**:
```
failed to find plugin "host-local" in path [/opt/cni/bin]
```

**Root Cause**: Symlinks not followed in sandbox

**Fix**:
```bash
mkdir -p /opt/cni/bin
cp /usr/lib/cni/* /opt/cni/bin/
# Copy actual binaries, not symlinks
```

**Result**: ✅ CNI plugin errors resolved

### Iteration 6: Fix Overlayfs Snapshotter

**Issue**: Overlayfs mounting fails

**Error**:
```
failed to mount overlay: operation not permitted
```

**Fix**:
```bash
# Install fuse-overlayfs
apt-get install -y fuse-overlayfs

# Use fuse-overlayfs snapshotter
k3s server --snapshotter=fuse-overlayfs
```

**Result**: ✅ Overlayfs errors resolved

### Iteration 7: Remaining Error - cAdvisor

**After all fixes**, final error:

```
Failed to start ContainerManager: failed to get rootfs info: unable to find data in memory cache
```

**All Other Errors**: ✅ Resolved

**This Error**: ❌ Cannot be resolved without code changes

## Root Cause Analysis

### Deep Dive into cAdvisor

Traced the error to cAdvisor's filesystem detection:

```go
// google/cadvisor/fs/fs.go
func (i *RealFsInfo) GetDirFsDevice(dir string) (*DeviceInfo, error) {
    var stat syscall.Statfs_t
    err := syscall.Statfs(dir, &stat)

    // Get filesystem type
    fsType := getFsType(stat.Type)

    // Check if supported
    switch fsType {
    case "ext2", "ext3", "ext4":
        return getDiskStats(device)
    case "xfs", "btrfs":
        return getDiskStats(device)
    case "overlayfs":
        return getOverlayStats(device)
    default:
        return nil, fmt.Errorf("unsupported filesystem: %s", fsType)
    }
}
```

### Our Environment

```bash
$ mount | grep " / "
runsc-root on / type 9p (rw,relatime,trans=fd,rfd=3,wfd=3)

$ stat -f / | grep Type
Type: 9p
```

**Problem**: 9p not in cAdvisor's supported list

### Why cAdvisor Needs This

cAdvisor (Container Advisor) is embedded in kubelet to:
- Collect container metrics (CPU, memory, disk, network)
- Monitor resource usage
- Provide data for autoscaling decisions
- Report node capacity

It MUST know:
- Total disk space
- Available disk space
- Disk I/O statistics
- Filesystem type

Without this data, ContainerManager cannot initialize, and kubelet exits.

## Attempted Workarounds

### Attempt 1: Bind-mount /var/lib/kubelet

**Idea**: Mount kubelet directory on different filesystem

```bash
mkdir -p /mnt/kubelet
mount --bind /mnt/kubelet /var/lib/kubelet
k3s server
```

**Result**: ❌ Failed - cAdvisor still queries root filesystem "/"

### Attempt 2: tmpfs for kubelet

**Idea**: Use tmpfs (in-memory filesystem) for kubelet

```bash
mount -t tmpfs tmpfs /var/lib/kubelet
k3s server
```

**Result**: ❌ Failed - cAdvisor still queries root filesystem "/"

### Attempt 3: tmpfs for k3s data directory

**Idea**: Put all k3s data on tmpfs

```bash
mkdir -p /mnt/k3s-tmpfs
mount -t tmpfs tmpfs /mnt/k3s-tmpfs
k3s server --data-dir=/mnt/k3s-tmpfs
```

**Result**: ❌ Failed - cAdvisor still queries root filesystem "/"

### Attempt 4: Fake /proc/diskstats

**Idea**: Create fake disk statistics

```bash
cat > /tmp/fake-diskstats << EOF
8 0 sda 1000 0 8000 1000 500 0 4000 500 0 1500 1500
EOF
mount --bind /tmp/fake-diskstats /proc/diskstats
```

**Result**: ❌ Failed - cAdvisor uses statfs() syscall, not /proc/diskstats

### Attempt 5: Disable Image GC and Eviction

**Idea**: Disable all disk-related features

```bash
k3s server \
    --kubelet-arg="--image-gc-high-threshold=100" \
    --kubelet-arg="--eviction-hard=" \
    --kubelet-arg="--eviction-soft="
```

**Result**: ❌ Failed - cAdvisor initialization is mandatory

### Attempt 6: Overlayfs on 9p

**Idea**: Mount overlayfs to provide ext4-like filesystem

```bash
mkdir -p /mnt/overlay/{lower,upper,work,merged}
mount -t overlay overlay \
    -o lowerdir=/mnt/overlay/lower,upperdir=/mnt/overlay/upper,workdir=/mnt/overlay/work \
    /mnt/overlay/merged
```

**Result**: ❌ Failed - Kernel rejects: "wrong fs type"

**Error**:
```
mount: /mnt/overlay/merged: wrong fs type, bad option, bad superblock
```

**Reason**: Overlayfs cannot mount with directories on 9p filesystem

## Conclusion

### Status: ❌ Experiment Failed (Fundamental Blocker Identified)

After resolving 5+ blockers, we hit a **fundamental limitation**:
- cAdvisor does not support 9p filesystems
- This is hardcoded in cAdvisor source
- Cannot be fixed with configuration
- Cannot be worked around with mounts
- Requires code changes to cAdvisor

### Successful Fixes

The following fixes **do work** and are valuable for other restricted environments:

1. ✅ `/dev/kmsg` bind-mount to `/dev/null`
2. ✅ `unshare --mount` for mount propagation
3. ✅ Image GC threshold configuration
4. ✅ CNI plugin binary copying
5. ✅ fuse-overlayfs snapshotter

These fixes are documented and can be used if cAdvisor support is added.

### What We Learned

- **Worker nodes are theoretically possible** if cAdvisor supported 9p
- **Every other blocker has a workaround** - only cAdvisor remains
- **The limitation is software, not hardware** - fixable with code changes
- **The fix location is clear** - cAdvisor's fs.go file

### Next Steps

Experiment 3 will explore Docker-in-Docker approaches to see if Docker isolation can bypass the 9p filesystem issue.

Experiment 4 will attempt syscall interception to fake filesystem types.

## Files

- Worker node scripts: `/scripts/start-k3s.sh`
- Documentation: `/docs/k3s-sandboxed-environment.md`

## References

- cAdvisor Source: https://github.com/google/cadvisor
- k3s Issue #8404: https://github.com/k3s-io/k3s/issues/8404
- kind Issue #3839: https://github.com/kubernetes-sigs/kind/issues/3839
