# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a research project investigating the feasibility of running Kubernetes (k3s) worker nodes in highly restricted sandbox environments (gVisor/runsc with 9p virtual filesystems), specifically targeting Claude Code web sessions.

**🎉 BREAKTHROUGH #1** (2025-11-22): Discovered that k3s requires CNI plugins even with `--disable-agent`. Created minimal fake CNI plugin that enables **native k3s control-plane** (no Docker required)!

**🚀 BREAKTHROUGH #2** (2025-11-22): Experiment 13 resolved ALL 6 fundamental blockers for worker nodes! Enhanced ptrace interceptor + --local-storage-capacity-isolation=false + iptables-legacy = functional worker nodes.

**🎊 BREAKTHROUGH #3** (2025-11-22): Experiment 15 achieves stable k3s worker node! Post-start hook panic is NOT fatal + --flannel-backend=none = stable k3s running 15+ minutes with kubectl fully operational!

**🔬 FUNDAMENTAL LIMITATION** (2025-11-22): Experiments 16-17 identified the exact blocker for pod execution - runc requires real kernel-backed cgroup files. Cannot be faked in userspace, FUSE blocked by gVisor, ptrace causes performance issues. **~97% of Kubernetes works, pod execution blocked by environment.**

**🔍 BOUNDARY CONFIRMED** (2025-11-24): Experiment 24 definitively confirmed the isolation boundary - the `runc init` subprocess runs in a completely isolated container namespace where NO workarounds can reach (LD_PRELOAD, ptrace, FUSE, or userspace files).

**Status**:
- ✅ **Control-plane**: PRODUCTION-READY (native k3s with fake CNI)
- ✅ **Worker node API layer**: 100% functional (kubectl works, 15+ min stability)
- ❌ **Pod execution**: BLOCKED (requires real kernel cgroup subsystem)

## Quick Start Commands

### 🚀 Automatic Startup (NEW!)

**The environment now starts automatically!** The SessionStart hook will:
1. Install all development tools (kubectl, helm, k3s, etc.)
2. Start the production-ready k3s control-plane
3. Configure kubectl environment variables

```bash
# After session starts, k3s is already running!
# Just use kubectl directly:
kubectl get namespaces

# Or test with Helm:
helm create testchart
helm install test ./testchart/
kubectl get all
```

### ⚡ Manual Quick Start (if needed)

```bash
# Manually start k3s (if not auto-started)
sudo bash tools/quick-start.sh

# Or start control-plane directly:
sudo bash solutions/control-plane-native/start-k3s-native.sh
export KUBECONFIG=/tmp/k3s-control-plane/kubeconfig.yaml
kubectl get namespaces
```

### Start k3s Control Plane (Production-Ready - Experiment 05) ⭐

```bash
# Start native k3s control-plane with fake CNI plugin
sudo bash solutions/control-plane-native/start-k3s-native.sh

# Configure kubectl
export KUBECONFIG=/tmp/k3s-control-plane/kubeconfig.yaml

# Verify it works
kubectl get namespaces

# Test with Helm
helm create testchart
helm install test ./testchart/
kubectl get all
```

### Alternative: Docker-based Control Plane (Legacy)

```bash
# Older approach using Docker (still works, but native is better)
sudo bash solutions/control-plane-docker/start-k3s-docker.sh
export KUBECONFIG=/root/.kube/config
kubectl get namespaces --insecure-skip-tls-verify
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

### Research Worker Node (API Layer Works, Pod Execution Blocked)

```bash
# Experiment 15: STABLE WORKER NODE ⭐ (15+ minute stability)
cd experiments/15-stable-wait-monitoring
bash run-wait-and-monitor.sh
# Result: k3s runs 15+ min, kubectl 100% functional, API layer works
# Limitation: Pods cannot execute (cgroup blocker)

# Experiments 16-17: Pod Execution Research (FUNDAMENTAL BLOCKER IDENTIFIED)
cd experiments/16-helm-chart-deployment
# Result: Pods reach ContainerCreating, blocked by runc cgroup requirement

cd experiments/17-inotify-cgroup-faker
# Result: Proved inotify works, but cannot fake cgroup files in userspace
# Finding: runc requires real kernel-backed cgroup files (cannot be faked)

# Experiment 13: Ultimate solution (6/6 k3s blockers resolved)
cd experiments/13-ultimate-solution
bash run-ultimate-solution.sh
# Result: All k3s startup blockers resolved, runs 20+ seconds

# Experiments 11-12: Critical discoveries
# - Exp 11: tmpfs cgroup support discovery
# - Exp 12: --local-storage-capacity-isolation=false flag

# Experiments 06-10: Alternative approaches tested
# - Exp 06: Enhanced ptrace (causes performance issues)
# - Exp 07: FUSE cgroups (gVisor blocks I/O operations)
# - Exp 08: Hybrid approach (components blocked)
# - Exp 09-10: LD_PRELOAD and bind mounts (partially successful)
```

## Repository Architecture

### Directory Structure

```
├── research/          # Research documentation
│   ├── research-question.md
│   ├── methodology.md
│   ├── findings.md
│   └── conclusions.md
├── experiments/       # Chronological experiments (01-32)
│   ├── 01-control-plane-only/
│   ├── 05-fake-cni-breakthrough/       # ← BREAKTHROUGH #1: Fake CNI
│   ├── 13-ultimate-solution/           # ← BREAKTHROUGH #2: 6/6 blockers resolved
│   ├── 15-wait-and-retry/              # ← BREAKTHROUGH #3: 15+ min stability
│   ├── 24-docker-runtime-exploration/  # ← BOUNDARY CONFIRMED
│   ├── 32-preload-images/              # ← 100% achievement
│   └── EXPERIMENTS-INDEX.md            # Complete index of all experiments
├── solutions/         # Production-ready implementations
│   ├── control-plane-native/           # ← RECOMMENDED (Exp 05)
│   ├── control-plane-docker/           # Legacy
│   └── worker-ptrace-experimental/     # Proof-of-concept (Exp 04)
├── docs/              # Technical documentation
│   ├── QUICK-REFERENCE.md    # Command reference
│   ├── TESTING-GUIDE.md      # Testing procedures
│   ├── summaries/            # Research summaries
│   └── proposals/            # Upstream contribution proposals
├── tools/             # Automation scripts and utilities
│   ├── setup-claude.sh       # Auto-installs all tools
│   ├── quick-start.sh        # One-command cluster startup
│   └── README.md             # Tools documentation
└── .claude/hooks/     # Automation hooks
    └── SessionStart          # Auto-starts environment
```

### Key Scripts

**tools/quick-start.sh** ← ONE-COMMAND START ⚡
- Auto-starts production-ready control-plane
- Waits for cluster readiness
- Displays status and helpful examples
- Perfect for new sessions

**solutions/control-plane-native/start-k3s-native.sh** ← PRODUCTION-READY
- Native k3s control-plane with fake CNI plugin (Experiment 05)
- Starts in ~15-20 seconds
- Fully stable, runs indefinitely
- Perfect for Helm chart development

**experiments/15-wait-and-retry/run-wait-and-monitor.sh**
- Stable k3s worker node (Experiment 15)
- 15+ minute stability, kubectl 100% functional
- API layer works completely

**tools/setup-claude.sh** (Auto-runs via SessionStart hook)
- Installs container runtime (podman, docker CLI, buildah)
- Installs Kubernetes tools (k3s, kubectl, containerd)
- Installs development tools (helm, helm-unittest, kubectx)
- Installs research tools (inotify-tools, strace, lsof)

## Critical Technical Context

### The Fundamental Blocker (Experiments 16-17, 24)

Pod execution cannot work because:
1. ✅ k3s server starts successfully (Experiment 15)
2. ✅ kubectl operations work 100%
3. ✅ Pods get scheduled to node
4. ✅ Pods reach ContainerCreating status
5. ❌ **runc init subprocess fails** ← BLOCKED HERE
   - The `runc init` subprocess runs in an **isolated container namespace**
   - This subprocess requires `/proc/sys/kernel/cap_last_cap`
   - **Subprocess Isolation Boundary** (Experiment 24):
     - LD_PRELOAD environment variables don't propagate
     - Ptrace can only trace direct children, not sub-subprocess
     - FUSE emulation → gVisor blocks I/O operations (Experiment 07)
     - Userspace files → rejected as inauthentic (Experiment 17)
   - Enhanced ptrace → cannot reach subprocess (Experiment 06)
6. ❌ Pod never reaches Running status

**Process Hierarchy:**
```
k3s → kubelet → containerd → runc (parent) → runc init (subprocess)
                                   ↑              ↓
                          Workarounds work    ISOLATION BOUNDARY
                                               Workarounds STOP
```

**This cannot be worked around in userspace. Requires kernel-level support that gVisor intentionally restricts.**

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

### Worker Node Research Approaches

**Experiment 04: Basic Ptrace** (Proven Concept)
- Intercepts open() and openat() syscalls
- Redirects /proc/sys/* paths to /tmp/fake-procsys/*
- Enables kubelet to start, but unstable (30-60s runtime)
- Location: solutions/worker-ptrace-experimental/

**Experiment 06: Enhanced Ptrace** (Testing)
- Extends Exp 04 with statfs() syscall interception
- Spoofs 9p filesystem type as ext4 to fool cAdvisor
- Expected: Extended stability beyond 60 seconds
- Location: experiments/06-enhanced-ptrace-statfs/

**Experiment 07: FUSE cgroup Emulation** (Testing)
- Virtual cgroupfs filesystem using FUSE
- Provides cgroup files cAdvisor needs for metrics
- Clean alternative to ptrace for cgroup access
- Location: experiments/07-fuse-cgroup-emulation/

**Experiments 09-10: Creative Alternatives** (Research)
- Exp 09: LD_PRELOAD library interception (works perfectly, but k3s is statically-linked Go)
- Exp 10: Direct bind mounts (proven viable in gVisor!)
- Identified exact upstream cAdvisor fix needed (1-line change)
- Location: experiments/09-ld-preload-intercept/, experiments/10-bind-mount-cgroups/
- Summary: experiments/EXPERIMENTS-09-10-SUMMARY.md

**Experiments 11-12: Flag Discoveries** (Breakthroughs)
- Exp 11: tmpfs is supported by cAdvisor (was mounting 9p files incorrectly)
- Exp 12: --local-storage-capacity-isolation=false ELIMINATES cAdvisor error!
- Location: experiments/11-tmpfs-cgroup-mount/, experiments/12-complete-solution/
- Summary: experiments/EXPERIMENTS-11-13-SUMMARY.md

**Experiment 13: Ultimate Solution** ⭐ (MAJOR SUCCESS)
- Combines ALL working techniques from all experiments
- Enhanced ptrace interceptor with dynamic /proc/sys/* redirection
- --local-storage-capacity-isolation=false (Exp 12)
- iptables-legacy workaround
- Fake CNI plugin (Exp 05)
- Location: experiments/13-ultimate-solution/
- **Result: 6/6 fundamental blockers RESOLVED!**
- kube-proxy starts successfully (first time ever!)
- API server handles requests
- k3s runs for ~20 seconds
- Remaining: API server timing issue (solvable optimization challenge)

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
# Check k3s status
systemctl status k3s

# View k3s logs
journalctl -u k3s -f

# Restart k3s
systemctl restart k3s

# Stop k3s
systemctl stop k3s

# Re-run setup (quick-start)
sudo bash tools/quick-start.sh
```

### Accessing the Cluster

```bash
# Kubeconfig is auto-configured by SessionStart hook!
# Default location: /tmp/k3s-control-plane/kubeconfig.yaml

# Test cluster access (no TLS verification needed for control-plane)
kubectl get namespaces

# Or manually set if needed
export KUBECONFIG=/tmp/k3s-control-plane/kubeconfig.yaml
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
- docs/summaries/RESEARCH-SUMMARY.md - Consolidated research summary
- experiments/EXPERIMENTS-INDEX.md - Complete experiment index

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
- Installs container runtime (podman, docker CLI, buildah)
- Installs Kubernetes tools (k3s, kubectl, containerd)
- Installs development tools (helm, helm-unittest, kubectx, kubens)
- Installs research tools (inotify-tools, strace, lsof)
- **🚀 Automatically starts k3s control-plane** (NEW!)
- Configures KUBECONFIG environment variable
- Displays "Environment Ready!" status

**The environment is now fully automated - k3s is running and ready to use immediately after session startup!**

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
