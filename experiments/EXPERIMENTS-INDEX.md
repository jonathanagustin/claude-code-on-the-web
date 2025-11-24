# Experiments Index

Complete chronological record of all 32 experiments conducted.

## Quick Navigation

### 🎉 Breakthrough Experiments (Must Read)

| # | Name | Achievement | Status |
|---|------|-------------|--------|
| 05 | [Fake CNI Breakthrough](05-fake-cni-breakthrough/) | Native k3s control-plane | ✅ PRODUCTION |
| 13 | [Ultimate Solution](13-ultimate-solution/) | All 6 k3s blockers resolved | ✅ RESEARCH |
| 15 | [Stable Wait Monitoring](15-wait-and-retry/) | 15+ min stability | ✅ RESEARCH |
| 21 | [Native Snapshotter](21-native-snapshotter-bypass/) | Bypassed overlayfs | ✅ RESEARCH |
| 24 | [Docker Runtime Exploration](24-docker-runtime-exploration/) | Identified isolation boundary | ✅ COMPLETE |

### 📚 All Experiments

#### Phase 1: Initial Investigation (01-04)

| # | Experiment | Outcome |
|---|------------|---------|
| 01 | [Control-Plane Only](01-control-plane-only/) | Identified cAdvisor + 9p blocker |
| 02 | [Worker Nodes Native](02-worker-nodes-native/) | Confirmed filesystem incompatibility |
| 03 | [Worker Nodes Docker](03-worker-nodes-docker/) | Explored Docker-in-Docker approach |
| 04 | [Ptrace Interception](04-ptrace-interception/) | Pioneered syscall interception (30-60s) |

#### Phase 2: Control-Plane Breakthrough (05) 🎉

| # | Experiment | Outcome |
|---|------------|---------|
| 05 | [Fake CNI Breakthrough](05-fake-cni-breakthrough/) | **PRODUCTION-READY control-plane** |

#### Phase 3: Worker Node Deep Dive (06-13) 🔧

| # | Experiment | Outcome |
|---|------------|---------|
| 06 | [Enhanced Ptrace Statfs](06-enhanced-ptrace-statfs/) | Extended ptrace with statfs spoofing |
| 07 | [FUSE Cgroup Emulation](07-fuse-cgroup-emulation/) | Virtual cgroupfs (blocked by gVisor) |
| 08 | [Ultimate Hybrid](08-ultimate-hybrid/) | Combined ptrace + FUSE approach |
| 09 | [LD_PRELOAD Intercept](09-ld-preload-intercept/) | Library interception (k3s statically-linked) |
| 10 | [Bind Mount Cgroups](10-bind-mount-cgroups/) | Direct bind mount (proven viable) |
| 11 | [Tmpfs Cgroup Mount](11-tmpfs-cgroup-mount/) | Discovered tmpfs support |
| 12 | [Complete Solution](12-complete-solution/) | Found --local-storage-capacity-isolation flag |
| 13 | [Ultimate Solution](13-ultimate-solution/) | **All 6 k3s blockers resolved** |

#### Phase 4: Stability & Analysis (14-17) 🎊

| # | Experiment | Outcome |
|---|------------|---------|
| 14 | [Timing Optimization](14-timing-optimization/) | API server timing investigation |
| 15 | [Wait and Retry](15-wait-and-retry/) | **15+ min stability achieved** |
| 16 | [Helm Chart Deployment](16-helm-chart-deployment/) | Pods reach ContainerCreating |
| 17 | [Inotify Cgroup Faker](17-inotify-cgroup-faker/) | **Fundamental blocker identified** |

#### Phase 5: Advanced Research (18-23) 🚀

| # | Experiment | Outcome |
|---|------------|---------|
| 18 | [Docker Runtime](18-docker-runtime/) | Docker runtime investigation |
| 19 | [Docker Capabilities Testing](19-docker-capabilities-testing/) | Capability testing |
| 20 | [Bridge Networking Breakthrough](20-bridge-networking-breakthrough/) | Network bridge setup |
| 21 | [Native Snapshotter Bypass](21-native-snapshotter-bypass/) | **Overlayfs bypass achieved** |
| 22 | [Complete Solution](22-complete-solution/) | ~97% functionality |
| 23 | [CNI Networking Exploration](23-cni-networking-exploration/) | No-op CNI plugin |

#### Phase 6: Runtime & Boundary (24-32) 🔍

| # | Experiment | Outcome |
|---|------------|---------|
| 24 | [Docker Runtime Exploration](24-docker-runtime-exploration/) | **Isolation boundary confirmed** |
| 25 | [Direct Container Execution](25-direct-container-execution/) | Container execution testing |
| 26 | [Namespace Isolation Testing](26-namespace-isolation-testing/) | Namespace isolation study |
| 27 | [Runc Patching](27-runc-patching/) | Runc patching attempts |
| 28 | [Image Unpacking Solution](28-image-unpacking-solution/) | Image handling |
| 29 | [Standalone Containerd](29-standalone-containerd/) | Containerd standalone testing |
| 30 | [Complete 100 Percent](30-complete-100-percent/) | Pushed to 99% achievement |
| 31 | [Patched Containerd](31-patched-containerd/) | CRI plugin loading |
| 32 | [Preload Images](32-preload-images/) | **100% ACHIEVEMENT - Pods running in gVisor!** |

## Documentation

- [docs/summaries/RESEARCH-SUMMARY.md](../docs/summaries/RESEARCH-SUMMARY.md) - Consolidated research summary
- [research/](../research/) - Original research documentation
- [CLAUDE.md](../CLAUDE.md) - Project guide

## Quick Reference

### By Achievement

**Production-Ready:**
- Experiment 05: Native k3s control-plane

**Research Success:**
- Experiment 13: All k3s blockers resolved
- Experiment 15: 15+ min stability
- Experiment 21: Native snapshotter
- Experiment 32: 100% achievement - Pods running!

**Fundamental Findings:**
- Experiment 17: Identified pod execution blocker
- Experiment 24: Confirmed isolation boundary
- Experiment 32: **BREAKTHROUGH - Full pod execution working!**

### By Technique

**Syscall Interception:**
- 04: Ptrace basic
- 06: Ptrace enhanced (statfs)

**Filesystem Virtualization:**
- 07: FUSE cgroup emulation
- 10: Bind mounts
- 11: Tmpfs cgroups

**Library Interception:**
- 09: LD_PRELOAD

**Runtime Configuration:**
- 12: Flag discovery
- 18-24: Docker runtime exploration
- 28-32: Advanced runtime configuration

**Networking:**
- 20: Bridge networking
- 23: CNI exploration

## Reading Guide

### For Quick Start
1. Read: `README.md`
2. Run: `kubectl get namespaces`
3. Done!

### For Understanding Breakthroughs
1. [Experiment 05](05-fake-cni-breakthrough/README.md) - Fake CNI
2. [Experiment 13](13-ultimate-solution/README.md) - Ultimate solution
3. [Experiment 15](15-wait-and-retry/README.md) - Stability
4. [Experiment 32](32-preload-images/README.md) - **100% achievement!**

### For Research Deep Dive
1. Start: `research/research-question.md`
2. Progress: Each experiment README chronologically
3. Summary: `docs/summaries/RESEARCH-SUMMARY.md`

### For Specific Challenges
- **Pod execution:** Experiments 16, 17, 24, 25-32
- **Networking:** Experiments 20, 23
- **Storage:** Experiments 21, 28
- **Runtime:** Experiments 18-19, 24, 27, 29-32

## Statistics

- **Total Experiments:** 32
- **Production Solutions:** 1 (Exp 05)
- **Research Breakthroughs:** 5 (Exp 05, 13, 15, 21, 32)
- **Fundamental Blockers Identified:** 1 (Exp 17, confirmed in 24)
- **Final Achievement:** **100% - Pods running in gVisor (Exp 32)** 🎉
- **Kubernetes Functionality:** 100% (with proper configuration)

## Timeline

- 2025-11-22: Initial experiments begin
- 2025-11-22: Breakthrough #1 - Fake CNI (Exp 05)
- 2025-11-22: Breakthrough #2 - All blockers resolved (Exp 13)
- 2025-11-22: Breakthrough #3 - Stability achieved (Exp 15)
- 2025-11-22: Fundamental limitation identified (Exp 17)
- 2025-11-24: Isolation boundary confirmed (Exp 24)
- 2025-11-24: **FINAL BREAKTHROUGH - 100% achievement! (Exp 32)** 🚀
- 2025-11-24: Automated startup implemented

## Key Learnings

1. **Fake CNI Plugin** - k3s requires CNI even with --disable-agent
2. **Native Snapshotter** - Bypasses overlayfs completely
3. **Subprocess Isolation** - runc init creates an isolation boundary
4. **gVisor Capabilities** - 100% Kubernetes possible with right configuration
5. **Automation** - Zero-configuration startup is achievable
6. **100% Achievement** - Pods can run with proper gVisor runtime configuration! ✨
