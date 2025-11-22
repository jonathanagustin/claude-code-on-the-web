# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a research project investigating the feasibility of running Kubernetes (k3s) worker nodes in highly restricted sandbox environments (gVisor/runsc with 9p virtual filesystems), specifically targeting Claude Code web sessions.

**Key Finding**: Control-plane-only mode works perfectly for Helm chart development; full worker nodes are blocked by cAdvisor's inability to recognize 9p filesystems.

## Quick Start Commands

### Start k3s Control Plane (Recommended)

```bash
# Start control-plane-only k3s cluster (stable, production-ready)
sudo bash solutions/control-plane-docker/start-k3s-docker.sh

# Configure kubectl
export KUBECONFIG=/root/.kube/config

# Verify it works
kubectl get namespaces --insecure-skip-tls-verify

# Test with Helm
helm create testchart
helm install test ./testchart/
kubectl get all
```

### Development Workflow

```bash
# Lint and validate Helm charts
helm lint ./chart/
helm template test ./chart/ --debug

# Install chart to control-plane
helm install myrelease ./chart/
kubectl get all

# Upgrade with different values
helm upgrade myrelease ./chart/ --set image.tag=v2.0

# Uninstall
helm uninstall myrelease
```

### Experimental Worker Node (Unstable)

```bash
# Build and run ptrace-based worker (30-60s runtime)
cd solutions/worker-ptrace-experimental
./setup-k3s-worker.sh build
./setup-k3s-worker.sh run
```

## Repository Architecture

### Directory Structure

```
├── research/          # Research documentation (methodology, findings)
│   ├── research-question.md
│   ├── methodology.md
│   ├── findings.md
│   └── conclusions.md
├── experiments/       # Chronological experiments (01-04)
│   ├── 01-control-plane-only/
│   ├── 02-worker-nodes-native/
│   ├── 03-worker-nodes-docker/
│   └── 04-ptrace-interception/
├── solutions/         # Production-ready implementations
│   ├── control-plane-docker/      # Recommended solution
│   └── worker-ptrace-experimental/ # Unstable proof-of-concept
├── tools/            # Setup scripts and utilities
└── docs/             # Technical deep-dive documentation
```

### Key Scripts

**solutions/control-plane-docker/start-k3s-docker.sh**
- Production-ready control-plane-only k3s in Docker
- Starts in ~30 seconds
- Fully stable, runs indefinitely
- Perfect for Helm chart development

**solutions/worker-ptrace-experimental/setup-k3s-worker.sh**
- Experimental ptrace-based syscall interceptor
- Enables worker nodes for 30-60 seconds
- Proof-of-concept only, unstable
- Written in C, intercepts /proc/sys access

**tools/setup-claude.sh**
- Auto-runs via .claude/hooks/SessionStart
- Installs container runtime, k3s, kubectl, helm
- Only runs when CLAUDE_CODE_REMOTE=true

**tools/start-k3s.sh**
- Native k3s with worker node attempt
- Documented but non-functional due to cAdvisor limitations

## Critical Technical Context

### The Fundamental Blocker

Worker nodes cannot run because:
1. kubelet requires ContainerManager to start
2. ContainerManager requires cAdvisor.GetRootFsInfo("/")
3. cAdvisor only supports: ext4, xfs, btrfs, overlayfs
4. This environment uses 9p virtual filesystem (gVisor)
5. cAdvisor returns "unable to find data in memory cache"
6. kubelet exits immediately

**This is hardcoded in cAdvisor source code and cannot be worked around via configuration.**

### Successfully Resolved Blockers

During research, we fixed multiple issues that would have prevented k3s startup:

```bash
# /dev/kmsg workaround (from Kubernetes-in-Docker)
touch /dev/kmsg
mount --bind /dev/null /dev/kmsg

# Mount propagation fix
unshare --mount --propagation unchanged bash -c 'mount --make-rshared /'

# Image GC thresholds
--kubelet-arg="--image-gc-high-threshold=100"
--kubelet-arg="--image-gc-low-threshold=99"

# CNI plugins (copy, don't symlink)
cp /usr/lib/cni/host-local /opt/cni/bin/host-local
```

These fixes brought us to the final blocker (cAdvisor filesystem incompatibility).

### Ptrace Interception Approach

The experimental worker solution uses ptrace to intercept syscalls:
- Attaches to k3s process with PTRACE_ATTACH
- Intercepts open() and openat() syscalls
- Redirects /proc/sys/* paths to /tmp/fake-procsys/*
- Enables kubelet to start, but unstable (30-60s runtime)

**Location**: solutions/worker-ptrace-experimental/ptrace_interceptor.c

Limitations:
- Cannot emulate cgroup pseudo-filesystem
- cAdvisor still periodically detects 9p
- Performance overhead: ~2-5x on intercepted syscalls

## What Works vs What Doesn't

### ✅ Control-Plane-Only Mode (Fully Functional)

- API Server, Scheduler, Controller Manager
- CoreDNS
- kubectl operations (create, get, describe, delete)
- Helm install/upgrade/uninstall
- Resource creation (Deployments, Services, ConfigMaps, CRDs)
- RBAC configuration
- Server-side dry runs
- API compatibility validation

### ❌ Not Functional (Requires External Cluster)

- Pod execution (pods stay Pending - no worker node)
- Container logs (kubectl logs)
- Container exec (kubectl exec)
- Service networking (no endpoints without running pods)
- Ingress routing
- Persistent volume mounting

## Common Development Tasks

### Helm Chart Development

Control-plane-only mode provides everything needed:

```bash
# Lint chart
helm lint ./chart/

# Validate template rendering
helm template test ./chart/ --debug

# Test installation
helm install myrelease ./chart/

# Verify resources created
kubectl get all

# Test RBAC
kubectl auth can-i list pods --as=system:serviceaccount:default:myapp

# Server-side validation
kubectl apply -f deployment.yaml --dry-run=server
```

### Testing Changes

```bash
# Check logs
docker logs k3s-server

# Restart k3s
docker restart k3s-server

# Stop and remove
docker stop k3s-server && docker rm k3s-server

# Re-run setup
sudo bash solutions/control-plane-docker/start-k3s-docker.sh
```

### Accessing the Cluster

```bash
# Set kubeconfig
export KUBECONFIG=/root/.kube/config

# Skip TLS verification (self-signed cert)
kubectl get nodes --insecure-skip-tls-verify

# Or configure in kubeconfig
kubectl config set-cluster default --insecure-skip-tls-verify=true
```

## Environment Details

**Target Platform**: Claude Code web sessions
- **Sandbox**: gVisor (runsc) with restricted kernel access
- **Filesystem**: 9p (Plan 9 Protocol) virtual filesystem
- **OS**: Linux 4.4.0
- **Capabilities**: Limited CAP_SYS_ADMIN, CAP_SYS_PTRACE available
- **k3s Version**: v1.33.5-k3s1 (later v1.34.1)

**Filesystem Detection**:
```bash
mount | grep " / "
# Output: runsc-root on / type 9p (rw,relatime,trans=fd,rfd=3,wfd=3)
```

## Research Documentation

Each experiment follows structured documentation:
1. **Hypothesis** - Expected outcome
2. **Method** - Exact commands executed
3. **Results** - Actual outcome
4. **Analysis** - Root cause analysis
5. **Next Steps** - Follow-up actions

**Primary Documents**:
- research/research-question.md - Original research question
- research/methodology.md - Experimental approach
- research/findings.md - Detailed results with evidence
- research/conclusions.md - Final recommendations
- docs/technical-deep-dive.md - Complete technical summary

## Related Upstream Issues

This limitation is known in the community:
- [k3s-io/k3s#8404](https://github.com/k3s-io/k3s/issues/8404) - Same cAdvisor error
- [kubernetes-sigs/kind#3839](https://github.com/kubernetes-sigs/kind/issues/3839) - Filesystem compatibility
- Multiple GitPod/Cloud IDE reports with same issue

## Recommendations for Future Work

### For Helm Chart Development
Use control-plane-only solution (solutions/control-plane-docker) - fully functional and stable.

### For Full Integration Testing
- External k3s cluster
- k3d/kind on local machine (requires Docker Desktop VM)
- Cloud Kubernetes cluster (EKS, GKE, AKS)

### For Research Continuation
- Investigate cAdvisor patches to support 9p
- Explore eBPF-based filesystem virtualization
- Test with newer gVisor releases
- Investigate alternative container runtimes

## SessionStart Hook

The `.claude/hooks/SessionStart` script automatically runs when a Claude Code session starts:
- Runs tools/setup-claude.sh (if CLAUDE_CODE_REMOTE=true)
- Installs kubectl, helm, k3s, container runtimes
- Configures KUBECONFIG environment variable
- Displays helpful commands

## Important Caveats

**When modifying scripts**:
- Test in Claude Code web environment (CLAUDE_CODE_REMOTE=true)
- Ensure idempotency (safe to run multiple times)
- This environment is sandboxed - some operations will fail by design

**Security context**:
- Research conducted in authorized sandbox
- No attempt to break out of sandbox
- Focus on legitimate development workflows
- Ethical use of ptrace for syscall interception

**Performance notes**:
- Control-plane startup: ~30 seconds
- Memory usage: ~200-300MB
- Ptrace overhead: 2-5x slowdown on intercepted syscalls
