# Research Methodology

## Environment Setup

### Target Platform
- **Environment**: Claude Code web sessions
- **Sandbox**: gVisor (runsc) with restricted kernel access
- **OS**: Linux 4.4.0
- **Filesystem**: 9p (Plan 9 Protocol) virtual filesystem
- **Capabilities**: Limited CAP_SYS_ADMIN, CAP_SYS_PTRACE available

### Tools & Technologies
- **Kubernetes Distribution**: k3s v1.33.5-k3s1 (later v1.34.1)
- **Container Runtime**: containerd (embedded in k3s)
- **Alternative Runtimes**: Docker, Podman (tested)
- **Debugging Tools**: strace, ptrace, procfs inspection

## Research Phases

### Phase 1: Baseline Exploration (Native k3s)

**Objective**: Determine if k3s runs out-of-the-box

**Method**:
```bash
# Simple installation attempt
curl -sfL https://get.k3s.io | sh -
k3s server
```

**Data Collection**:
- Error messages and stack traces
- Log file analysis (`/var/log/k3s.log`)
- System call traces (`strace -f k3s server`)
- Missing file/device identification

**Expected Outcomes**:
- Document all errors
- Categorize blockers (filesystem, cgroup, device, permissions)
- Prioritize issues by severity

### Phase 2: Systematic Blocker Resolution

**Objective**: Address each blocker individually

**Method**: Iterative fix-and-test cycle

1. **Identify specific error**
   ```bash
   # Example: /dev/kmsg missing
   open /dev/kmsg: no such file or directory
   ```

2. **Research solutions**
   - Search k3s/Kubernetes issue trackers
   - Review kind (Kubernetes-in-Docker) source code
   - Analyze similar sandboxed environments

3. **Implement workaround**
   ```bash
   # Example: Bind-mount /dev/null to /dev/kmsg
   touch /dev/kmsg
   mount --bind /dev/null /dev/kmsg
   ```

4. **Test and validate**
   - Run k3s server
   - Check for new errors
   - Document fix effectiveness

5. **Repeat** for next blocker

**Documented Fixes**:
- `/dev/kmsg` → bind-mount `/dev/null`
- Mount propagation → `unshare --mount --propagation unchanged`
- Image GC thresholds → `--image-gc-high-threshold=100`
- CNI plugins → copy binaries (not symlink)

### Phase 3: Alternative Approaches

**Objective**: Explore containerization and virtualization workarounds

#### Experiment 3A: Control-Plane-Only Mode
```bash
k3s server --disable-agent
```

**Hypothesis**: Control plane might work without worker/kubelet

**Validation**:
- API server accessibility
- kubectl command functionality
- Helm chart deployment (scheduled but not running)

#### Experiment 3B: Docker-in-Docker
```bash
docker run -d --privileged k3s:latest server
```

**Hypothesis**: Docker isolation might bypass 9p filesystem issues

**Variations Tested**:
- Default storage driver (overlay2)
- VFS storage driver
- Privileged vs non-privileged
- Different k3s flags

#### Experiment 3C: Filesystem Layering
```bash
# Attempt overlayfs on 9p
mount -t overlay overlay -o lowerdir=...,upperdir=...,workdir=... /mnt/overlay
```

**Hypothesis**: Overlayfs might provide ext4-like filesystem to cAdvisor

**Testing**:
- Native overlayfs mounting
- fuse-overlayfs alternative
- tmpfs for specific directories

### Phase 4: Advanced Workarounds (Ptrace Interception)

**Objective**: Intercept syscalls to redirect /proc/sys access

**Approach**: Develop ptrace-based interceptor

#### Design
1. **Parent Process**: Ptrace interceptor (C program)
2. **Child Process**: k3s server (traced)
3. **Interception**: open() and openat() syscalls
4. **Redirection**: `/proc/sys/*` → `/tmp/fake-procsys/*`

#### Implementation
```c
// Pseudo-code
ptrace(PTRACE_ATTACH, k3s_pid);
while (true) {
    ptrace(PTRACE_SYSCALL, k3s_pid);  // Wait for syscall
    if (syscall == SYS_OPEN || syscall == SYS_OPENAT) {
        path = read_string_from_child_memory();
        if (path.startsWith("/proc/sys/")) {
            fake_path = "/tmp/fake-procsys/" + path.removePrefix("/proc/sys/");
            write_string_to_child_memory(fake_path);
        }
    }
    ptrace(PTRACE_SYSCALL, k3s_pid);  // Continue syscall
}
```

#### Validation
- Syscall redirection success rate
- k3s startup without /proc/sys errors
- Runtime stability
- Performance overhead measurement

### Phase 5: Root Cause Analysis

**Objective**: Identify fundamental, unfixable limitations

**Method**: Deep dive into cAdvisor source code

**Investigation**:
1. Review cAdvisor filesystem detection logic
2. Trace `GetRootFsInfo()` execution
3. Identify hardcoded filesystem type checks
4. Determine why 9p is not recognized

**Key Finding**:
```go
// cAdvisor source (simplified)
func GetRootFsInfo() (*FsInfo, error) {
    fs := detectFilesystem("/")
    switch fs {
        case "ext4", "xfs", "btrfs", "overlayfs":
            return collectStats(fs)
        default:
            return nil, errors.New("unable to find data in memory cache")
    }
}
```

**Conclusion**: 9p not in supported list, cAdvisor cannot initialize

## Data Collection

### Quantitative Metrics
- **Startup time**: Time from k3s start to error/success
- **Stability duration**: How long does k3s run before crashing
- **Success rate**: Percentage of startup attempts that succeed
- **Performance overhead**: Ptrace interception latency

### Qualitative Observations
- Error message patterns
- Workaround complexity
- Usability for development workflows
- Documentation quality requirements

## Validation Criteria

### Control-Plane Success
```bash
kubectl get namespaces         # Must succeed
kubectl create namespace test  # Must succeed
helm install test ./chart/     # Must succeed (scheduled state OK)
```

### Worker Node Success
```bash
kubectl get nodes              # Must show Ready status
kubectl run nginx --image=nginx  # Pod must enter Running state
kubectl logs nginx             # Must show container logs
```

### Stability Testing
```bash
# Run for 60+ minutes
while true; do
    kubectl get nodes
    sleep 60
done
```

## Documentation Standards

Each experiment documented with:
1. **Hypothesis** - What we expected
2. **Method** - Exact commands run
3. **Results** - What actually happened
4. **Analysis** - Why it happened
5. **Next Steps** - What to try next

## Reproducibility

All experiments include:
- Exact version numbers
- Complete command sequences
- Environment variables
- Configuration files
- Expected vs actual outputs

## Ethical Considerations

- Research conducted in authorized sandbox environment
- No attempt to break out of sandbox
- No exploitation of security vulnerabilities
- Focus on legitimate development use cases
