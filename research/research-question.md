# Research Question

## Primary Question

**Can we run a full Kubernetes cluster (control plane + worker nodes) inside sandboxed web development environments with restricted kernel access and virtual filesystems?**

## Context

Modern web-based development environments (like Claude Code, GitHub Codespaces, GitPod) run in sandboxed containers for security and isolation. These environments have significant restrictions:

- **No privileged operations** - Cannot perform kernel-level operations
- **Virtual filesystems** - Use 9p or other virtual filesystem protocols instead of native ext4/xfs
- **Limited cgroup access** - Restricted access to control groups for resource management
- **No raw device access** - Cannot access `/dev/kmsg` and other kernel devices
- **Nested containerization limits** - Running containers within containers faces restrictions

## Motivation

### Developer Pain Points

1. **External dependency** - Developers need external Kubernetes clusters to test deployments
2. **Context switching** - Must leave IDE to test on remote clusters
3. **Cost** - Cloud clusters incur ongoing costs
4. **Latency** - Network delays when working with remote clusters
5. **Reproducibility** - "Works on my cluster" problems

### Desired Workflow

Developers should be able to:
```bash
# Within their web IDE
$ kubectl apply -f deployment.yaml
$ helm install myapp ./chart/
$ kubectl logs -f myapp
```

All without leaving the browser or requiring external infrastructure.

## Specific Sub-Questions

1. **Control Plane**: Can we run the Kubernetes control plane (API server, scheduler, controller-manager)?

2. **Worker Nodes**: Can we run kubelet and container runtime in a sandboxed environment?

3. **Container Execution**: Can we actually run pods and containers?

4. **Filesystem Compatibility**: How do Kubernetes components handle 9p virtual filesystems?

5. **cgroup Requirements**: Can we work around limited cgroup access?

6. **Workarounds**: What syscall-level or userspace tricks can bypass restrictions?

## Success Criteria

### Minimum Viable Success
- ✅ Control plane operational
- ✅ kubectl commands work
- ✅ Can validate Helm charts
- ✅ Useful for development workflows

### Full Success
- ✅ Worker node operational
- ✅ Pods can be scheduled
- ✅ Containers can run
- ✅ Networking functions
- ✅ Stable for >1 hour runtime

### Stretch Goals
- ✅ Multi-node cluster
- ✅ Storage provisioning
- ✅ Production-grade stability

## Out of Scope

- Running production workloads in sandboxed environments
- High-performance computing scenarios
- Security hardening beyond sandbox defaults
- Custom kernel modifications (not possible in sandboxes)

## Research Approach

1. **Exploratory Phase** - Try native k3s and document errors
2. **Analysis Phase** - Identify root causes and blockers
3. **Workaround Phase** - Develop solutions for each blocker
4. **Validation Phase** - Test stability and usability
5. **Documentation Phase** - Document findings and recommendations

## Expected Challenges

Based on initial investigation:
- cAdvisor filesystem compatibility
- cgroup pseudo-filesystem access
- Device node availability
- Mount propagation restrictions
- Overlayfs support on 9p
- Nested container networking

## Related Research

- Kubernetes-in-Docker (kind) - Similar challenges with Docker Desktop
- k3s on constrained devices - IoT and edge computing scenarios
- gVisor container runtime - Running containers in gVisor sandboxes
- Rootless containers - Running without privileged access
