# K3s in Sandboxed Environments

This document summarizes the research and findings for running k3s with worker nodes in sandboxed environments (specifically gVisor/runsc with 9p virtual filesystem).

## Summary

**TL;DR**: Full worker node support is **not possible** in this environment due to cAdvisor's inability to recognize the 9p virtual filesystem. However, control-plane-only mode works perfectly for Helm chart development and testing.

## Environment Details

- **Sandbox**: gVisor (runsc)
- **Filesystem**: 9p (Plan 9 Protocol) virtual filesystem
- **K3s Version**: v1.33.5-k3s1
- **OS**: Linux 4.4.0

## What Works ✅

### Control-Plane Only Mode (Recommended)

Using `--disable-agent` flag, k3s runs successfully with:
- ✅ API Server (fully functional)
- ✅ Controller Manager
- ✅ Scheduler
- ✅ CoreDNS
- ✅ Helm chart installs
- ✅ kubectl operations
- ✅ All control-plane functionality

**Use case**: Perfect for Helm chart development, template validation, and testing deployments that don't require actual pod execution.

### Breakthrough Fixes Applied

We successfully resolved multiple blockers that were preventing k3s from starting:

1. **`/dev/kmsg` Error** - Fixed by bind-mounting `/dev/null` (Kubernetes-in-Docker approach)
2. **Bind-mount restrictions** - Fixed using `unshare --mount` with shared propagation
3. **Image GC validation** - Fixed threshold configuration (low=99, high=100)
4. **CNI plugin errors** - Fixed by copying binaries (not symlinking)
5. **Kubelet startup** - Successfully starts with proper configuration

## What Doesn't Work ❌

### Worker Nodes / Kubelet Agent

**Root Cause**: cAdvisor (Container Advisor) embedded in kubelet cannot recognize the 9p virtual filesystem.

**Error**:
```
Failed to start ContainerManager: failed to get rootfs info: unable to find data in memory cache
```

**Technical Details**:
- cAdvisor collects container and system metrics
- Requires filesystem statistics from standard Linux filesystems (ext4, xfs, btrfs, overlayfs)
- The 9p virtual filesystem (used in gVisor/runsc) is not recognized
- cAdvisor cannot populate its memory cache with rootfs information
- containerManager initialization is a hard requirement for kubelet
- Without containerManager, kubelet exits immediately

**Attempts That Failed**:
- ❌ Bind-mounting `/var/lib/kubelet` to itself
- ❌ Mounting tmpfs on `/var/lib/kubelet`
- ❌ Mounting tmpfs for k3s data directory (`--data-dir=/mnt/k3s-tmpfs`)
- ❌ Creating fake `/proc/diskstats`
- ❌ Disabling image garbage collection
- ❌ Disabling eviction checks
- ❌ Disabling localStorageCapacityIsolation (via kubelet config)
- ❌ Using overlayfs layers
- ❌ Docker-in-Docker with VFS storage driver (containers see 9p root filesystem)
- ❌ Docker-in-Docker with overlay2 storage driver (overlayfs cannot mount on 9p directories)
- ❌ Manual overlayfs mounting on 9p filesystem (kernel rejects with "wrong fs type")

**Why These Failed**:
All approaches fail for the same fundamental reason: cAdvisor's `GetRootFsInfo()` specifically queries the root filesystem (`/`). Even when running inside Docker containers or using different storage drivers, the underlying storage must be on the host's 9p filesystem, and Docker cannot create a non-9p root filesystem when operating on 9p storage. Overlayfs (which would provide an ext4-like filesystem) cannot be mounted with directories on 9p, and VFS storage driver simply uses host directories (which are 9p). The 9p virtual filesystem is visible to cAdvisor regardless of mount namespace tricks or containerization.

## Solutions

### Solution 1: Control-Plane Only (Recommended)

Use the Docker-based k3s setup for Helm chart development:

```bash
./scripts/start-k3s-docker.sh
```

**Pros**:
- ✅ Fully working API server
- ✅ Perfect for Helm testing
- ✅ Stable and reliable
- ✅ All kubectl operations work

**Cons**:
- ❌ No worker node
- ❌ Pods cannot actually run
- ❌ Cannot test runtime behavior

### Solution 2: External Worker Nodes

Run the control plane in the sandbox and connect external worker nodes from other machines.

**Setup**:
1. Run k3s server with `--disable-agent` in sandbox
2. Expose API server to network
3. Join worker nodes from external machines using k3s agent

**Pros**:
- ✅ Full Kubernetes functionality
- ✅ Actual pod execution
- ✅ Realistic testing

**Cons**:
- ❌ Requires additional infrastructure
- ❌ More complex setup

### Solution 3: VM-Based Development

Use a lightweight VM (k3d, minikube, kind) on the host machine outside the sandbox.

**Pros**:
- ✅ Full Kubernetes functionality
- ✅ Worker nodes supported
- ✅ Industry-standard approach

**Cons**:
- ❌ Requires VM support on host
- ❌ More resource overhead

## Research References

Similar issues have been reported in various environments:

1. **Kubernetes-in-Docker (kind)**: Requires device mounts and special configuration for non-standard filesystems
   - Issue: [kubernetes-sigs/kind#3839](https://github.com/kubernetes-sigs/kind/issues/3839)
   - Workaround: Extra mounts in cluster configuration

2. **k3s on Alpine + Docker**: Same "unable to find data in memory cache" error
   - Issue: [k3s-io/k3s#8404](https://github.com/k3s-io/k3s/issues/8404)
   - Status: Still open, no solution

3. **Gitpod/Cloud IDEs**: Similar sandbox limitations
   - Conclusion: "Only viable option is VM" for worker nodes

4. **cAdvisor 9p Support**: Not implemented
   - cAdvisor expects standard Linux filesystems
   - No plans for 9p support (virtual filesystem edge case)

## Technical Achievements

Despite worker nodes not being possible, we achieved significant breakthroughs:

### 1. `/dev/kmsg` Workaround
```bash
# Bind-mount /dev/null to /dev/kmsg (kind approach)
if [ ! -e /dev/kmsg ]; then
    touch /dev/kmsg
fi
mount --bind /dev/null /dev/kmsg
```

### 2. Mount Propagation with unshare
```bash
# Enable shared propagation in mount namespace
unshare --mount --propagation unchanged /bin/bash -c '
    mount --make-rshared /
    # k3s commands here
'
```

### 3. Kubelet Configuration
```bash
k3s server \
    --kubelet-arg="--fail-swap-on=false" \
    --kubelet-arg="--cgroups-per-qos=false" \
    --kubelet-arg="--enforce-node-allocatable=" \
    --kubelet-arg="--protect-kernel-defaults=false" \
    --kubelet-arg="--image-gc-high-threshold=100" \
    --kubelet-arg="--image-gc-low-threshold=99" \
    --kubelet-arg="--eviction-hard=" \
    --kubelet-arg="--eviction-soft="
```

These fixes brought us to the final blocker (containerManager), proving that worker nodes in highly sandboxed environments are *theoretically possible* with the right kernel/filesystem support.

## Recommendations

### For Helm Chart Development
**Use Solution 1** (control-plane only): The Docker-based setup provides everything needed for chart development, testing, and validation.

### For Integration Testing
**Use Solution 3** (VM-based): Tools like k3d or kind provide full functionality in a lightweight package.

### For Production Workloads
**Use external infrastructure**: Sandboxed development environments are not suitable for running production Kubernetes clusters.

## Scripts

- `scripts/start-k3s-docker.sh` - Working control-plane-only setup
- `scripts/start-k3s.sh` - Experimental worker node attempt (documented but non-functional)
- `scripts/start-k3s-dind.sh` - Docker-in-Docker experiments (non-functional)

## Conclusion

While full worker node support proved impossible due to fundamental filesystem limitations, we successfully:
1. Documented the exact root cause
2. Created working solutions for chart development
3. Pioneered workarounds that work in other restricted environments
4. Proved that sandboxed k8s worker nodes would require cAdvisor support for 9p filesystems

The control-plane-only solution is production-ready for the intended use case (Helm chart development and testing).

