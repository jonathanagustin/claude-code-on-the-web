# Quick Reference Guide

**Purpose**: Fast lookup for commands, file locations, and key concepts

**Last Updated**: 2025-11-22

## TL;DR - What Works Right Now

```bash
# ✅ PRODUCTION-READY: Control-plane (Experiment 05)
cd solutions/control-plane-native
sudo ./start-k3s-native.sh
export KUBECONFIG=/tmp/k3s-control-plane/kubeconfig.yaml
kubectl get namespaces  # Works perfectly!

# 🔧 EXPERIMENTAL: Worker nodes (Experiment 08)
cd experiments/08-ultimate-hybrid
sudo ./run-ultimate-k3s.sh  # Testing phase
```

## Experiments At-a-Glance

| # | Name | Status | Use When... |
|---|------|--------|-------------|
| 01 | Control-plane only | ✅ Superseded | Historical reference |
| 02 | Native workers | ✅ Complete | Understanding blockers |
| 03 | Docker workers | ✅ Complete | Understanding Docker limitations |
| 04 | Ptrace basic | ✅ Complete | Understanding ptrace approach |
| **05** | **Fake CNI** | ✅ **PRODUCTION** | **You want control-plane NOW** |
| 06 | Enhanced ptrace | 🔧 Testing | Testing filesystem spoofing |
| 07 | FUSE cgroups | 🔧 Testing | Testing cgroup emulation |
| 08 | Ultimate hybrid | 🔧 Testing | Testing full solution |

## File Locations

### Production Solutions
```
solutions/
├── control-plane-native/        ← USE THIS for control-plane
│   └── start-k3s-native.sh      ← Main script
└── control-plane-docker/         ← Legacy (pre-Exp05)
    └── start-k3s-docker.sh
```

### Experiments
```
experiments/
├── 01-control-plane-only/       Historical
├── 02-worker-nodes-native/      Historical
├── 03-worker-nodes-docker/      Historical
├── 04-ptrace-interception/      Historical
├── 05-fake-cni-breakthrough/    ← Control-plane solution
├── 06-enhanced-ptrace-statfs/   ← Testing: statfs() spoofing
├── 07-fuse-cgroup-emulation/    ← Testing: FUSE cgroupfs
└── 08-ultimate-hybrid/          ← Testing: All combined
```

### Documentation
```
├── BREAKTHROUGH.md              ← Experiment 05 discovery
├── RESEARCH-CONTINUATION.md     ← Experiments 06-08 summary
├── TESTING-GUIDE.md             ← Complete testing procedures
├── QUICK-REFERENCE.md           ← This file
└── research/
    ├── research-question.md     ← Original question
    ├── methodology.md           ← Research approach
    ├── findings.md              ← All findings (updated)
    └── conclusions.md           ← All conclusions (updated)
```

### Proposals
```
docs/proposals/
├── custom-kubelet-build.md      ← Upstream path #1
└── cadvisor-9p-support.md       ← Upstream path #2
```

## Common Commands

### Control-Plane (Experiment 05)

```bash
# Start
cd solutions/control-plane-native
sudo ./start-k3s-native.sh

# Use kubectl
export KUBECONFIG=/tmp/k3s-control-plane/kubeconfig.yaml
kubectl get namespaces
kubectl create deployment nginx --image=nginx
kubectl get deployments

# Stop
sudo killall k3s

# Troubleshoot
tail -f /tmp/k3s-control-plane/server/logs/api-server.log
```

### Enhanced Ptrace (Experiment 06)

```bash
# Build
cd experiments/06-enhanced-ptrace-statfs
sudo ./run-enhanced-k3s.sh build

# Test interceptor
sudo ./run-enhanced-k3s.sh test

# Run with k3s
sudo ./run-enhanced-k3s.sh

# Monitor (in another terminal)
watch -n 5 'kubectl --insecure-skip-tls-verify get nodes'
```

### FUSE cgroups (Experiment 07)

```bash
# Build
cd experiments/07-fuse-cgroup-emulation
sudo ./run-k3s-with-fuse-cgroups.sh build

# Test FUSE only
sudo ./test_fuse.sh

# Test FUSE mount
sudo ./run-k3s-with-fuse-cgroups.sh test-fuse

# Run with k3s
sudo ./run-k3s-with-fuse-cgroups.sh
```

### Ultimate Hybrid (Experiment 08)

```bash
# Build all
cd experiments/08-ultimate-hybrid
sudo ./run-ultimate-k3s.sh build

# Component test
sudo ./run-ultimate-k3s.sh test

# Full run
sudo ./run-ultimate-k3s.sh

# Monitor (multiple terminals)
# Terminal 1: Main output
# Terminal 2: watch -n 5 'kubectl --insecure-skip-tls-verify get nodes'
# Terminal 3: tail -f /tmp/k3s-ultimate/server/logs/kubelet.log
```

## Key Concepts

### The Fundamental Blocker

**Problem**: cAdvisor (in kubelet) only supports specific filesystems
```go
// Hardcoded in cAdvisor
supportedFS := []string{"ext4", "xfs", "btrfs", "overlayfs"}
// 9p NOT supported!
```

**Impact**: Worker nodes can't start in gVisor (which uses 9p)

### The Breakthrough (Experiment 05)

**Discovery**: k3s requires CNI plugins even with `--disable-agent`

**Solution**: Minimal fake CNI plugin
```bash
#!/bin/bash
echo '{"cniVersion": "0.4.0", "ips": [{"version": "4", "address": "10.244.0.1/24"}]}'
```

**Result**: Control-plane works perfectly!

### Multi-Layer Emulation (Experiment 08)

**Layer 1**: Fake CNI → Control-plane initialization
**Layer 2**: Ptrace → `/proc/sys` redirection + `statfs()` spoofing
**Layer 3**: FUSE → Virtual cgroupfs

**Goal**: Worker nodes stable 60+ minutes

## Troubleshooting Quick Reference

### "API server never starts"

```bash
# Check k3s running
ps aux | grep k3s

# Check logs
ls -la /tmp/k3s-*/server/logs/
tail -f /tmp/k3s-*/server/logs/api-server.log

# Check CNI plugin
ls -la /opt/cni/bin/host-local
cat /opt/cni/bin/host-local  # Should be bash script

# Restart clean
sudo killall k3s
sudo rm -rf /tmp/k3s-*
sudo ./start-k3s-native.sh
```

### "kubectl: connection refused"

```bash
# Check KUBECONFIG set
echo $KUBECONFIG

# Set manually
export KUBECONFIG=/tmp/k3s-control-plane/kubeconfig.yaml

# Or use flag
kubectl --kubeconfig=/tmp/k3s-control-plane/kubeconfig.yaml get ns

# Skip TLS if needed
kubectl --insecure-skip-tls-verify get namespaces
```

### "Worker node NotReady"

```bash
# Expected for control-plane-only mode (Exp 05)
# There ARE no worker nodes!

# For experiments 06-08, check:
tail -f /tmp/k3s-*/server/logs/kubelet.log | grep -i error

# Common errors:
# "unable to find data in memory cache" → cAdvisor 9p issue
# "failed to get rootfs info" → Filesystem detection
# "cgroup" errors → Missing cgroup files
```

### "FUSE mount fails"

```bash
# Check FUSE available
which fusermount
lsmod | grep fuse

# Unmount stuck mount
sudo fusermount -u /tmp/fuse-cgroup

# Check permissions
ls -la /tmp/fuse-cgroup

# Install if missing
sudo apt-get install fuse libfuse-dev
```

### "Compilation errors"

```bash
# Enhanced ptrace
cd experiments/06-enhanced-ptrace-statfs
gcc -o enhanced_ptrace_interceptor enhanced_ptrace_interceptor.c

# FUSE cgroupfs
cd experiments/07-fuse-cgroup-emulation
pkg-config --exists fuse || echo "Install: sudo apt-get install libfuse-dev"
gcc -Wall fuse_cgroupfs.c -o fuse_cgroupfs `pkg-config fuse --cflags --libs`
```

## Success Indicators

### Control-Plane Success (Exp 05)

```bash
# Should see:
kubectl get namespaces
# NAME              STATUS   AGE
# default           Active   Xs
# kube-system       Active   Xs

# Should work:
kubectl create namespace test  # ✅
kubectl create deployment nginx --image=nginx  # ✅
kubectl get deployments  # ✅

# Won't work (expected):
kubectl logs nginx-xxx  # ❌ No worker nodes
```

### Worker Node Success (Exp 06-08)

```bash
# Minimal success:
kubectl get nodes
# NAME        STATUS   ROLES                  AGE   VERSION
# localhost   Ready    control-plane,master   Xs    vX.XX+k3s1

# Good success:
# Node stays Ready for >5 minutes

# Complete success:
# Node stays Ready for 60+ minutes
# Pods can be scheduled (may stay Pending without full runtime)
```

## Environment Check

```bash
# Quick environment validation
cat > /tmp/env-check.sh << 'EOF'
#!/bin/bash
echo "Environment Check"
echo "================="

echo -n "Sandbox: "
[[ "$CLAUDE_CODE_REMOTE" == "true" ]] && echo "✅ Claude Code" || echo "❌ Not web"

echo -n "Filesystem: "
mount | grep " / " | grep -q 9p && echo "✅ 9p" || echo "❌ Not 9p"

echo -n "k3s: "
which k3s > /dev/null && echo "✅ Installed" || echo "❌ Missing"

echo -n "kubectl: "
which kubectl > /dev/null && echo "✅ Installed" || echo "❌ Missing"

echo -n "gcc: "
which gcc > /dev/null && echo "✅ Installed" || echo "❌ Missing"

echo -n "FUSE: "
pkg-config --exists fuse && echo "✅ Available" || echo "❌ Missing"

echo -n "Root: "
[[ $EUID -eq 0 ]] && echo "✅ Running as root" || echo "⚠️ Not root (needed for k3s)"
EOF

chmod +x /tmp/env-check.sh
/tmp/env-check.sh
```

## Status Summary Table

| Component | Exp 05 (Control) | Exp 06 (Ptrace) | Exp 07 (FUSE) | Exp 08 (Hybrid) |
|-----------|------------------|-----------------|---------------|-----------------|
| API Server | ✅ Works | ✅ Works | ✅ Works | ✅ Works |
| Scheduler | ✅ Works | ✅ Works | ✅ Works | ✅ Works |
| kubectl | ✅ Works | ✅ Works | ✅ Works | ✅ Works |
| Kubelet | ❌ Disabled | 🔧 Testing | 🔧 Testing | 🔧 Testing |
| Worker Node | ❌ No | 🔧 Testing | 🔧 Testing | 🔧 Testing |
| Pod Execution | ❌ No | ❌ Unlikely | ❌ Unlikely | ⚠️ Maybe |
| **Production Ready** | **✅ YES** | **🔧 Testing** | **🔧 Testing** | **🔧 Testing** |

## Next Actions Decision Tree

```
Start here
    │
    ├─ Want control-plane only?
    │   └─ YES → Use Experiment 05 ✅
    │       └─ solutions/control-plane-native/start-k3s-native.sh
    │
    ├─ Want to test worker nodes?
    │   ├─ Start simple → Test Experiment 06 (ptrace + statfs)
    │   ├─ Test cgroups → Test Experiment 07 (FUSE)
    │   └─ Go all-in → Test Experiment 08 (ultimate hybrid)
    │
    ├─ Want to contribute upstream?
    │   ├─ cAdvisor approach → docs/proposals/cadvisor-9p-support.md
    │   └─ Kubelet approach → docs/proposals/custom-kubelet-build.md
    │
    └─ Want to understand research?
        ├─ Overview → BREAKTHROUGH.md, RESEARCH-CONTINUATION.md
        ├─ Details → research/findings.md, research/conclusions.md
        └─ Testing → TESTING-GUIDE.md
```

## Contact & Links

**Repository**: This research project
**Related Issues**:
- k3s-io/k3s#8404
- kubernetes-sigs/kind#3839

**Documentation**:
- gVisor: https://gvisor.dev
- k3s: https://k3s.io
- cAdvisor: https://github.com/google/cadvisor

---

**Quick Reference Version**: 1.0
**Last Updated**: 2025-11-22
**Maintained By**: Research Team
