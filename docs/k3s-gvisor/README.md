# K3s Worker Nodes in gVisor Sandbox

This directory contains the solution for running k3s with full worker functionality inside gVisor sandboxed environments (like Claude Code).

## Quick Start

```bash
# 1. Build the ptrace interceptor
cd docs/k3s-gvisor
./setup-k3s-worker.sh build

# 2. Start k3s with worker
./setup-k3s-worker.sh run

# 3. Check status
./setup-k3s-worker.sh status

# 4. View logs
./setup-k3s-worker.sh logs

# 5. Use kubectl
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
```

## Problem Statement

gVisor provides a sandboxed environment with restricted kernel access. When running k3s worker nodes in gVisor, several critical /proc/sys paths are missing or read-only, causing kubelet's ContainerManager to fail initialization.

### Original Error

```
Failed to start ContainerManager" err="[
  open /proc/sys/kernel/keys/root_maxkeys: no such file or directory,
  open /proc/sys/kernel/keys/root_maxbytes: no such file or directory,
  write /proc/sys/vm/overcommit_memory: input/output error,
  open /proc/sys/vm/panic_on_oom: no such file or directory,
  open /proc/sys/kernel/panic: no such file or directory,
  open /proc/sys/kernel/panic_on_oops: no such file or directory
]"
```

## Solution Architecture

### Components

1. **Ptrace-based Syscall Interceptor** (`ptrace_interceptor.c`)
   - Intercepts open() and openat() system calls
   - Redirects /proc/sys/* accesses to fake files
   - Works with statically-linked binaries
   - Handles multi-process tracing (fork/vfork/clone)

2. **Fake /proc/sys Filesystem** (`/tmp/fake-procsys/`)
   - Provides realistic kernel parameter values
   - Allows both read and write operations
   - Mimics expected /proc/sys structure

3. **Fuse-overlayfs Snapshotter**
   - gVisor doesn't support standard overlayfs
   - fuse-overlayfs provides userspace alternative
   - Required for container image layering

4. **CNI Plugin Configuration**
   - Ensures network plugins are in PATH
   - host-local and other CNI plugins available

### How It Works

```
┌─────────────────────────────────────────────────────────────┐
│  K3s Process (statically linked)                            │
│  ├─ open("/proc/sys/kernel/keys/root_maxkeys", O_RDONLY)    │
│  │                                                           │
│  └─ openat(AT_FDCWD, "/proc/sys/vm/overcommit_memory", ...) │
└──────────────────────┬──────────────────────────────────────┘
                       │ System call
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  Ptrace Interceptor (parent process)                        │
│  ├─ Detects syscall: SYS_OPEN / SYS_OPENAT                  │
│  ├─ Reads path from child's memory                          │
│  ├─ Checks if path matches /proc/sys/*                      │
│  ├─ Replaces path in child's memory with fake file          │
│  └─ Allows syscall to proceed                               │
└──────────────────────┬──────────────────────────────────────┘
                       │ Modified syscall
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  Kernel (gVisor)                                            │
│  ├─ Receives: open("/tmp/fake-procsys/kernel/keys/...")     │
│  └─ Returns: file descriptor to fake file                   │
└─────────────────────────────────────────────────────────────┘
```

### Why This Works

- **LD_PRELOAD doesn't work**: k3s is statically linked
- **Kernel mounts don't work**: No privileged operations in gVisor
- **Ptrace works because**:
  - Operates at syscall boundary
  - Process-agnostic (works with static binaries)
  - CAP_SYS_PTRACE is available in gVisor
  - Can modify syscall arguments before kernel sees them

## Files

- `ptrace_interceptor.c` - Syscall interceptor source code
- `setup-k3s-worker.sh` - Automated setup and management script
- `README.md` - This file
- `JOURNEY.md` - Detailed technical journey and lessons learned

## Requirements

### Software
- k3s (v1.34.1 or later)
- fuse-overlayfs
- CNI plugins (/usr/lib/cni)
- gcc (for building ptrace interceptor)

### Capabilities
- CAP_SYS_PTRACE (for syscall interception)
- IS_SANDBOX environment variable (indicates gVisor)

### Verified In
- Claude Code gVisor sandbox
- Linux kernel 4.4.0
- gVisor/runsc runtime

## Current Status

### ✅ Working Components

- API Server
- Kube-scheduler
- Kube-controller-manager
- Kubelet (started successfully)
- Container runtime (containerd)
- CPU Manager
- Memory Manager
- Volume Manager
- Pod manifest watching

### ⚠️ Known Limitations

**Stability Warning**: K3s becomes unstable after 30-60 seconds due to repeated cAdvisor errors. Recommended for development, testing, and proof-of-concept only.

1. **ContainerManager cAdvisor cache error** (Recurring, non-fatal initially):
   ```
   Failed to start ContainerManager" err="failed to get rootfs info: unable to find data in memory cache"
   ```
   - Kubelet continues functioning despite this error
   - Error repeats and eventually causes k3s instability
   - Related to gVisor's limited /sys/fs/cgroup support
   - Impact: K3s runs for ~30-60 seconds before becoming unstable

2. **Missing cgroup files**: Some cgroup pseudo-files are unavailable
   ```
   open /sys/fs/cgroup/cpuacct/cpuacct.usage_percpu: no such file or directory
   ```
   - Fake files created but not recognized as valid cgroup interfaces
   - Contributes to cAdvisor cache issues

3. **Network devices**: Limited /sys/class/net access (informational only)
   ```
   Failed to get network devices: open /sys/class/net: no such file or directory
   ```
   - Does not prevent basic networking functionality

### Recommended Use Cases

**Good for:**
- Learning and experimentation with k3s in sandboxed environments
- Testing k3s components in gVisor
- Development and proof-of-concept work
- Understanding gVisor/runsc limitations
- Short-lived k3s instances (< 30 seconds)

**Not recommended for:**
- Production workloads
- Long-running k3s clusters
- Performance-critical applications
- Reliability-critical deployments

**Better alternatives for production:**
- External Kubernetes cluster with gVisor as container runtime
- K3s on host OS with gVisor for pod-level isolation

## Performance Considerations

### Overhead
- Ptrace introduces syscall overhead (2-5x slowdown per intercepted call)
- Only open/openat to /proc/sys paths are intercepted
- Most syscalls pass through without interception

### Optimization Opportunities
1. Use whitelisting for specific paths only
2. Cache file descriptor mappings
3. Minimize verbose logging in production

## Security Considerations

### Threat Model
- Running in gVisor already provides strong isolation
- Ptrace interceptor runs with same privileges as k3s
- Fake /proc/sys files are in /tmp (not affecting real kernel)

### Recommendations
- Review fake kernel parameter values for your use case
- Monitor ptrace interceptor for unexpected behavior
- Audit logs for security-relevant events

## Future Improvements

1. **Extend interception** to handle more /sys and /proc paths
2. **Mock cAdvisor data** to resolve ContainerManager initialization
3. **Optimize performance** with selective syscall filtering
4. **Add monitoring** for interceptor health and statistics
5. **Package as container** for easier distribution

## Contributing

See `JOURNEY.md` for implementation details if you want to extend or modify the solution.

## License

This solution is part of the claude-code-on-the-web repository and follows the same license.

## References

- [gVisor Documentation](https://gvisor.dev/)
- [Ptrace Manual](https://man7.org/linux/man-pages/man2/ptrace.2.html)
- [K3s Documentation](https://docs.k3s.io/)
- [FUSE OverlayFS](https://github.com/containers/fuse-overlayfs)

