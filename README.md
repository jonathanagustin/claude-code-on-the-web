# Running Kubernetes (k3s) in Sandboxed Environments

A research project exploring the feasibility of running Kubernetes worker nodes in highly restricted sandbox environments, specifically gVisor/runsc with 9p virtual filesystems.

## Research Question

**Can we run a full Kubernetes cluster (including worker nodes) inside sandboxed web development environments like Claude Code?**

This research was motivated by the desire to enable developers to test Kubernetes deployments, Helm charts, and containerized applications directly within sandboxed browser-based development environments without requiring external infrastructure.

## Executive Summary

### Key Findings

1. ✅ **Control-plane works perfectly** - API server, scheduler, and controller-manager function fully
2. ❌ **Worker nodes face fundamental limitations** - cAdvisor cannot recognize 9p virtual filesystems
3. ⚠️ **Experimental workaround exists** - Ptrace-based syscall interception enables workers (unstable, 30-60s runtime)
4. ✅ **Practical solution identified** - Control-plane-only mode meets most development needs

### Recommended Approach

For **Helm chart development and testing**: Use control-plane-only mode (fully functional, stable)

For **full integration testing**: Use external clusters or local VM-based solutions (k3d, kind)

For **experimentation**: Ptrace interception approach demonstrates theoretical possibility

## Repository Structure

```
├── research/           # Research documentation
│   ├── research-question.md
│   ├── methodology.md
│   ├── findings.md
│   └── conclusions.md
├── experiments/        # Chronological experiments
│   ├── 01-control-plane-only/
│   ├── 02-worker-nodes-native/
│   ├── 03-worker-nodes-docker/
│   └── 04-ptrace-interception/
├── solutions/          # Production-ready implementations
│   ├── control-plane-docker/
│   └── worker-ptrace-experimental/
├── tools/              # Setup and utility scripts
├── docs/               # Technical deep-dive documentation
└── .claude/            # Claude Code configuration
```

## Quick Start

### For Development (Recommended)

```bash
# Start control-plane-only k3s cluster
sudo bash solutions/control-plane-docker/start-k3s-docker.sh

# Test Helm charts
export KUBECONFIG=/root/.kube/config
kubectl get namespaces --insecure-skip-tls-verify
helm install myapp ./my-chart/
```

### For Experimentation (Unstable)

```bash
# Build and run ptrace-based worker nodes
cd solutions/worker-ptrace-experimental
./setup-k3s-worker.sh build
./setup-k3s-worker.sh run
```

## Research Journey

This project documented multiple approaches and their outcomes:

1. **Native k3s** - Identified fundamental blocker (cAdvisor + 9p filesystem)
2. **Docker-in-Docker** - Explored containerization workarounds (unsuccessful for workers)
3. **Control-plane-only** - Discovered practical solution for development workflows
4. **Ptrace interception** - Pioneered syscall-level workarounds (proof-of-concept)

See `research/` directory for detailed methodology and findings.

## Technical Contributions

### Breakthroughs Achieved

- `/dev/kmsg` workaround using bind-mount to `/dev/null`
- Mount propagation fixes with `unshare`
- Kubelet configuration for restricted environments
- Ptrace-based syscall interception for statically-linked binaries
- Comprehensive documentation of cAdvisor limitations

### Root Cause Analysis

The fundamental blocker for worker nodes is **cAdvisor's filesystem compatibility**:
- cAdvisor (embedded in kubelet) requires filesystem statistics
- Supports: ext4, xfs, btrfs, overlayfs
- Does NOT support: 9p virtual filesystem (used by gVisor)
- Cannot initialize ContainerManager without rootfs info
- This is a hard requirement with no configuration workaround

## Environment

**Target Platform**: Claude Code web sessions (gVisor/runsc sandbox)
- **Sandbox**: gVisor with restricted kernel access
- **Filesystem**: 9p (Plan 9 Protocol) virtual filesystem
- **OS**: Linux 4.4.0
- **Limitations**: No privileged operations, limited cgroup access

## Use Cases

### ✅ Supported Use Cases
- Helm chart development and validation
- Kubernetes manifest generation
- API server testing
- kubectl operations
- Template rendering and linting

### ❌ Not Supported (Requires External Cluster)
- Running actual pods
- Testing runtime behavior
- Performance testing
- Production workloads

## Documentation

- **Research Overview**: `research/` directory
- **Detailed Findings**: `docs/technical-deep-dive.md`
- **Experiment Details**: `experiments/*/README.md`
- **Solution Guides**: `solutions/*/README.md`

## Related Work

- [kubernetes-sigs/kind#3839](https://github.com/kubernetes-sigs/kind/issues/3839) - Similar filesystem issues
- [k3s-io/k3s#8404](https://github.com/k3s-io/k3s/issues/8404) - cAdvisor cache errors
- [gVisor Documentation](https://gvisor.dev/) - Sandbox architecture
- [cAdvisor](https://github.com/google/cadvisor) - Container metrics collection

## Contributing

This is a research repository documenting findings. If you discover new approaches or workarounds:

1. Document your experiment in `experiments/`
2. Update `research/findings.md` with new discoveries
3. Submit a pull request with clear documentation

## License

This project is for research and educational purposes.

## Acknowledgments

Research conducted as part of exploring Claude Code capabilities and limitations for Kubernetes development workflows.
