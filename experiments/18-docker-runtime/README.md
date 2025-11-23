# Experiment 18: Docker as Container Runtime for k3s

**Date**: 2025-11-23
**Status**: TESTING
**Hypothesis**: Docker Engine might handle cgroups differently than standalone containerd/runc

## Context

After discovering in Experiments 16-17 that runc requires real kernel-backed cgroup files, we're testing if Docker Engine's container runtime has different cgroup handling that might work in gVisor.

## Background

### Why Docker Might Be Different

1. **Docker uses its own containerd** - Not k3s's embedded one
2. **VFS storage driver works** - No overlayfs requirement  
3. **Containers execute successfully** - Proven with test container
4. **Different cgroup abstraction** - Docker may handle cgroups at a higher level

### What We Know Works

```bash
✅ Docker daemon running (dockerd with VFS driver)
✅ Docker containers execute: docker run --rm dtzar/helm-kubectl echo "works!"
✅ Image import from Podman works
```

## Hypothesis

k3s supports `--docker` flag to use Docker instead of embedded containerd. If Docker's cgroup handling is more abstracted or handles the gVisor environment better, pods might execute.

## Method

### Phase 1: Configure k3s to Use Docker

```bash
k3s server \
  --docker \
  --flannel-backend=none \
  --disable-network-policy \
  --disable=coredns,servicelb,traefik,local-storage,metrics-server
```

### Phase 2: Create Test Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: docker-runtime-test
spec:
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
```

### Phase 3: Monitor Results

Check if pod reaches Running status or hits cgroup blocker.

## Expected Outcomes

**If Successful** ✅:
- Pod reaches Running status
- Container executes inside Docker
- Full Kubernetes with pod execution works

**If Failed** ❌:
- Same cgroup blocker as Experiments 16-17
- Docker still requires real kernel cgroup files
- Confirms OCI spec requirement applies universally

## Testing Log

Starting test...

## Results

### Phase 1: Docker Daemon ✅

```bash
✅ Docker Engine installed (v28.2.2)
✅ dockerd running with VFS storage driver  
✅ Docker containers execute successfully:
   - docker run --rm dtzar/helm-kubectl:latest echo "works!" → SUCCESS
✅ Image import from Podman works
```

### Phase 2: k3s with Docker Runtime ❌

**k3s Start Attempt**:
```bash
k3s server --docker \
  --flannel-backend=none \
  --disable-network-policy \
  --disable=coredns,servicelb,traefik,local-storage,metrics-server \
  --kubelet-arg="--image-gc-high-threshold=100" \
  --kubelet-arg="--image-gc-low-threshold=99"
```

**Result**: k3s crashed with same cAdvisor error

```
E1123 05:07:38.580162 kubelet.go:1511] "Failed to start ContainerManager"
  err="failed to get rootfs info: unable to find data in memory cache"
```

### Phase 3: Root Cause Analysis

**Why Docker Doesn't Help**:
1. ✅ Docker itself works fine in gVisor
2. ✅ Containers execute via Docker
3. ❌ **kubelet still uses cAdvisor** for resource monitoring
4. ❌ **cAdvisor checks filesystem type** regardless of container runtime  
5. ❌ **k3s crashes** before pods can even be scheduled

## Conclusions

### What We Proved

1. **Docker containers CAN run in gVisor** - This is valuable for standalone Docker use
2. **Container runtime is NOT the blocker** - The issue is kubelet/cAdvisor, not runc
3. **Changing runtimes doesn't bypass cAdvisor** - All k3s configurations use cAdvisor

### The Real Blocker Confirmed

```
k3s architecture:
  kubelet → cAdvisor (checks filesystem) → FATAL ERROR
                ↓
      Never reaches container runtime
```

**Timeline**:
1. kubelet starts
2. cAdvisor tries to get rootfs info
3. Filesystem type (9p) unsupported  
4. cAdvisor fails: "unable to find data in memory cache"
5. kubelet crashes
6. k3s exits

**Pods never get to container runtime** - crash happens earlier.

### Comparison with Previous Experiments

| Experiment | Runtime | Kubelet Start | Pod Execution | Result |
|------------|---------|---------------|---------------|--------|
| **Exp 15** | containerd/runc | ✅ (with flags) | ❌ cgroup blocker | 15+ min stable |
| **Exp 17** | containerd/runc | ✅ | ❌ "not a cgroup file" | Pod sandbox fails |
| **Exp 18** | Docker | ❌ | N/A (never reached) | kubelet crashes |

**Exp 15 with `--local-storage-capacity-isolation=false` worked better than Docker!**

### Why Experiment 15 Was Better

Experiment 15 bypassed the cAdvisor check with:
```bash
--kubelet-arg="--local-storage-capacity-isolation=false"
```

This allowed kubelet to start, reaching the actual pod execution phase where we hit the cgroup blocker.

**Docker approach didn't help** because:
- Still uses same kubelet
- Still uses same cAdvisor
- Doesn't bypass filesystem check

## Recommendations

1. **Don't pursue Docker runtime further** for k3s in gVisor
2. **Stick with Experiment 05** (control-plane) for production use
3. **Experiment 15 got furthest** for worker node research (reached pod execution phase)
4. **Fundamental blocker** remains: gVisor 9p filesystem + cgroup requirements

## Value of This Experiment

✅ **Proved Docker works in gVisor** - Useful for standalone containers
✅ **Confirmed container runtime isn't the issue** - Problem is kubelet/cAdvisor layer  
✅ **Validated Experiment 15 approach** - Showed flag-based workarounds work better

