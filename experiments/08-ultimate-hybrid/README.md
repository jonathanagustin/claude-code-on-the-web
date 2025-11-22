# Experiment 8: Ultimate Hybrid Approach for Stable Worker Nodes

## Overview

This experiment represents the **culmination of all previous research**, combining every successful technique to achieve stable k3s worker nodes in highly restricted gVisor sandbox environments.

## Building Blocks

### ✅ Experiment 05: Fake CNI Plugin (Breakthrough)
**Achievement**: Fully functional control-plane
**Key Insight**: Minimal fake CNI plugin bypasses initialization blocker
**Contribution**: Eliminates control-plane issues entirely

### ⚠️ Experiment 04: Ptrace /proc/sys Interception
**Achievement**: Worker node starts, 30-60s stability
**Key Insight**: Ptrace can redirect syscalls at runtime
**Contribution**: Enables kubelet initialization

### 🔧 Experiment 06: Enhanced Ptrace with statfs()
**Achievement**: Filesystem type spoofing
**Key Insight**: cAdvisor uses statfs() to detect filesystems
**Contribution**: Makes 9p appear as ext4

### 🔧 Experiment 07: FUSE cgroup Emulation
**Achievement**: Virtual cgroup filesystem
**Key Insight**: FUSE can emulate kernel pseudo-filesystems
**Contribution**: Provides cgroup files cAdvisor needs

## Hypothesis

By combining **ALL** successful techniques simultaneously:
1. Fake CNI plugin (control-plane stability)
2. Enhanced ptrace with statfs() interception (filesystem spoofing)
3. FUSE cgroup emulation (cgroup file access)
4. All previous workarounds (/dev/kmsg, mount propagation, etc.)

We can achieve **stable worker nodes running for 60+ minutes** in the gVisor sandbox.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         k3s Server                           │
│  ┌────────────┐  ┌───────────┐  ┌──────────────────┐       │
│  │ API Server │  │ Scheduler │  │ Controller Mgr   │       │
│  └────────────┘  └───────────┘  └──────────────────┘       │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                    Kubelet (Agent)                    │   │
│  │  ┌──────────────┐  ┌────────────────┐               │   │
│  │  │ ContainerMgr │→│    cAdvisor     │               │   │
│  │  └──────────────┘  └────────┬───────┘               │   │
│  └─────────────────────────────┼───────────────────────┘   │
└────────────────────────────────┼───────────────────────────┘
                                  │
                    ┌─────────────┴────────────────┐
                    │  Enhanced Ptrace Interceptor │
                    │  (syscall-level redirection) │
                    └─────────────┬────────────────┘
                                  │
        ┌─────────────────────────┼──────────────────────┐
        │                         │                       │
   ┌────▼────┐            ┌──────▼──────┐        ┌──────▼──────┐
   │ open()  │            │  statfs()   │        │  read()     │
   │ /proc/  │            │  returns    │        │  /sys/fs/   │
   │  sys/*  │            │  ext4 not   │        │  cgroup/*   │
   │    ↓    │            │  9p         │        │     ↓       │
   │ /tmp/   │            │             │        │  FUSE       │
   │ fake-   │            │             │        │  cgroup     │
   │ procsys │            │             │        │  emulator   │
   └─────────┘            └─────────────┘        └─────────────┘

           Combined Effect: cAdvisor sees a functional environment
```

## Implementation

### Master Integration Script

**File**: `run-ultimate-k3s.sh`

Orchestrates all components:

```bash
#!/bin/bash
# Ultimate k3s worker node solution

# 1. Build all components
build_ptrace_interceptor
build_fuse_cgroupfs

# 2. Setup all workarounds
setup_fake_procsys          # Exp 04
setup_dev_kmsg              # Exp 01
setup_mount_propagation     # Exp 02
setup_fake_cni              # Exp 05

# 3. Start FUSE cgroup emulator
mount_fuse_cgroups          # Exp 07

# 4. Start k3s with enhanced ptrace
exec enhanced_ptrace_interceptor k3s server ...  # Exp 06
```

### Component Integration

**Ptrace Interceptor Extensions**:
- Intercept open/openat → redirect /proc/sys
- Intercept statfs/fstatfs → spoof filesystem type
- **NEW**: Intercept all /sys/fs/cgroup paths → redirect to FUSE mount

**FUSE cgroup Emulator**:
- Mount at /tmp/fuse-cgroup
- Provide all cgroup files cAdvisor needs
- Return realistic, consistent data

**Fake CNI Plugin**:
- Located at /opt/cni/bin/host-local
- Returns valid CNI JSON
- Enables control-plane initialization

## Expected Outcomes

### Scenario A: Complete Success ✅

**Metrics**:
- Worker node starts within 30 seconds
- Node remains Ready for 60+ minutes
- No cAdvisor errors in logs
- Pods can be scheduled (Pending → Running requires container runtime)

**Evidence**:
```bash
$ kubectl get nodes
NAME        STATUS   ROLES                  AGE   VERSION
localhost   Ready    control-plane,master   65m   v1.34.1+k3s1

$ kubectl logs -f k3s-pod  # No errors for 60+ minutes
```

**Conclusion**: Worker nodes SOLVED for sandboxed environments

### Scenario B: Partial Success ⚠️

**Metrics**:
- Worker node starts
- Stability improves (60s → 10+ minutes)
- Occasional cAdvisor warnings
- Node may transition Ready ↔ NotReady

**Evidence**:
- Fewer "unable to find data in memory cache" errors
- Some cgroup queries succeed
- Still occasional filesystem detection failures

**Conclusion**: Significant improvement, identify remaining gaps

### Scenario C: No Additional Improvement ❌

**Metrics**:
- Same 30-60s stability as Experiment 04
- FUSE cgroup not being used by cAdvisor
- statfs() interception not helping

**Evidence**:
- cAdvisor still detecting 9p
- Not reading from FUSE cgroup files
- Same error patterns

**Conclusion**: cAdvisor checks more than we're intercepting

## Testing Protocol

### Phase 1: Component Testing (10 minutes)

**Test each component independently**:

```bash
# Test 1: FUSE cgroup emulator
./test_fuse.sh

# Test 2: Enhanced ptrace with test program
cd ../06-enhanced-ptrace-statfs
./run-enhanced-k3s.sh test

# Test 3: Fake CNI plugin
/opt/cni/bin/host-local
```

**Success Criteria**: All component tests pass

### Phase 2: Integration Testing (30 minutes)

**Start full stack**:

```bash
sudo ./run-ultimate-k3s.sh
```

**Monitor**:
```bash
# Terminal 1: k3s logs
tail -f /var/log/k3s.log | grep -E "ERROR|WARN|cAdvisor"

# Terminal 2: Node status
watch -n 5 'kubectl get nodes'

# Terminal 3: Interceptor output
# Watch for syscall interception messages
```

**Success Criteria**:
- ✅ All components start without errors
- ✅ Node registers as Ready
- ✅ Stable for at least 5 minutes

### Phase 3: Stability Testing (60+ minutes)

**Long-running test**:

```bash
# Start ultimate k3s
sudo ./run-ultimate-k3s.sh &

# Monitor for 60 minutes
for i in {1..60}; do
    echo "=== Minute $i ==="
    kubectl get nodes
    sleep 60
done
```

**Data Collection**:
- Node status every minute
- Error count in logs
- Memory usage over time
- CPU usage patterns

**Success Criteria**:
- ✅ Node Ready for entire 60 minutes
- ✅ No increasing error rate
- ✅ Stable resource usage

### Phase 4: Functional Testing (Optional)

**Attempt pod scheduling**:

```bash
# Create test deployment
kubectl create deployment nginx --image=nginx

# Check pod status
kubectl get pods -o wide

# Describe pod
kubectl describe pod <pod-name>
```

**Expected**:
- Pod scheduled to node
- May stay Pending (no container runtime fully functional)
- Or may attempt to start container

**This tests beyond our scope** - we're proving worker node stability, not full container execution.

## Troubleshooting

### Issue 1: FUSE mount fails

**Symptoms**: "fusermount: failed to open /dev/fuse"

**Solution**:
- Check if FUSE is available in gVisor
- Try alternative: pure ptrace redirection without FUSE

### Issue 2: cAdvisor still sees 9p

**Symptoms**: "unsupported filesystem" errors continue

**Solution**:
- Verify statfs() interception is working
- Check interceptor is catching all statfs variants
- Add debug logging to see actual syscalls

### Issue 3: cgroup files not found

**Symptoms**: "no such file or directory" for cgroup files

**Solution**:
- Verify FUSE filesystem is mounted
- Check ptrace is redirecting paths
- Extend FUSE emulator with missing files

### Issue 4: Performance degradation

**Symptoms**: k3s extremely slow

**Solution**:
- Reduce ptrace verbosity
- Cache syscall results
- Profile to find bottleneck

## Comparison with All Approaches

| Approach | Control Plane | Worker Node | Stability | Complexity |
|----------|---------------|-------------|-----------|------------|
| **Exp 01-04** | ❌ | ⚠️ 30-60s | Low | Medium |
| **Exp 05** | ✅ | ❌ | Perfect | Low |
| **Exp 06** | ✅ | 🔧 Testing | TBD | Medium |
| **Exp 07** | ✅ | 🔧 Testing | TBD | High |
| **Exp 08 (This)** | ✅ | 🎯 Goal | **60+ min** | High |

## Success Metrics

### Minimum Viable Success

- [  ] k3s server starts successfully
- [  ] kubelet initializes without errors
- [  ] Node registers as Ready
- [  ] Stable for >10 minutes
- [  ] No exponentially increasing errors

### Full Success

- [  ] k3s server starts in <30 seconds
- [  ] Node remains Ready for 60+ minutes
- [  ] cAdvisor reports metrics without errors
- [  ] Pods can be scheduled
- [  ] No memory leaks or resource exhaustion

### Stretch Goals

- [  ] Containers can start (requires runtime fixes)
- [  ] Networking functions
- [  ] Multi-hour stability
- [  ] Production-ready for development workflows

## Next Steps

### If Successful

1. **Document** complete setup as production solution
2. **Package** as single script for easy deployment
3. **Add to SessionStart hook** for automatic setup
4. **Create tutorial** for other sandboxed environments
5. **Publish findings** to k3s/Kubernetes communities

### If Partially Successful

1. **Profile** to identify remaining bottlenecks
2. **Extend ptrace** to intercept additional syscalls
3. **Enhance FUSE** emulator with more cgroup files
4. **Test alternative** approaches (eBPF, LD_PRELOAD variants)

### If Unsuccessful

1. **Deep dive** cAdvisor source to find what we're missing
2. **Propose custom kubelet build** without cAdvisor
3. **Engage upstream** communities for sandbox support
4. **Document limitations** clearly for users

## Conclusion

Experiment 08 represents the **most comprehensive attempt** to achieve stable worker nodes in sandboxed environments. By combining every successful technique from previous experiments, we maximize the probability of success.

**Key Innovation**: Multi-layer emulation and interception at syscall, filesystem, and initialization levels

**Expected Impact**: If successful, enables full k3s clusters in web-based development environments

**Research Value**: Even partial success provides insights for upstream improvements

---

**Status**: Ready for implementation and testing
**Estimated Test Time**: 2-4 hours for full validation
**Risk Level**: Medium (builds on proven components)
**Potential Reward**: Complete solution to worker node problem
