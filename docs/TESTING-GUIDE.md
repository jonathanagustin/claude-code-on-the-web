# Comprehensive Testing Guide

**Purpose**: Step-by-step guide for testing all experiments systematically

**Last Updated**: 2025-11-22

## Overview

This guide provides structured testing procedures for all 8 experiments, from basic validation to advanced integration testing.

## Prerequisites

### Environment Requirements

```bash
# Check you're in the right environment
echo $CLAUDE_CODE_REMOTE  # Should be "true" for web sessions
uname -a  # Linux 4.4.0 (gVisor)
mount | grep " / " | grep 9p  # Should show 9p filesystem

# Required tools
which kubectl  # k3s bundled version
which helm     # For chart testing
which gcc      # For compiling C code
which docker   # Or podman
pkg-config --exists fuse  # For FUSE experiments
```

### Installation Check

```bash
# Verify k3s installed
k3s --version

# Verify container runtime
systemctl status containerd || systemctl status docker

# Check available capabilities
capsh --print
```

## Testing Matrix

| Experiment | Duration | Complexity | Prerequisites | Expected Outcome |
|------------|----------|------------|---------------|------------------|
| 05 - Fake CNI | 5 min | Low | None | ✅ Control-plane works |
| 06 - Enhanced Ptrace | 15 min | Medium | gcc, Exp 05 | 🔧 Worker >60s |
| 07 - FUSE cgroups | 20 min | High | libfuse-dev | 🔧 cgroup access |
| 08 - Ultimate Hybrid | 60+ min | High | All above | 🎯 Stable workers |

## Test Procedures

### Experiment 05: Fake CNI Plugin (Baseline)

**Goal**: Verify control-plane works perfectly

**Duration**: 5 minutes

**Steps**:

```bash
# 1. Navigate to solution directory
cd solutions/control-plane-native

# 2. Run startup script
sudo ./start-k3s-native.sh

# 3. Wait for API server (should be <30 seconds)
# Watch for: "k3s control plane is ready!"

# 4. Verify
export KUBECONFIG=/tmp/k3s-control-plane/kubeconfig.yaml
kubectl get namespaces

# Expected output:
# NAME              STATUS   AGE
# default           Active   Xs
# kube-system       Active   Xs
# kube-public       Active   Xs
# kube-node-lease   Active   Xs
```

**Success Criteria**:
- ✅ API server starts within 30 seconds
- ✅ kubectl commands work
- ✅ Can create namespaces/deployments
- ✅ No errors in logs

**Failure Modes**:
- ❌ "Waiting for API server..." hangs → Check k3s logs
- ❌ CNI plugin errors → Verify /opt/cni/bin/host-local exists
- ❌ Connection refused → Check if k3s process running

**Troubleshooting**:
```bash
# Check k3s is running
ps aux | grep k3s

# View logs
tail -f /tmp/k3s-control-plane/server/logs/api-server.log

# Kill and retry
sudo killall k3s
sudo ./start-k3s-native.sh
```

### Experiment 06: Enhanced Ptrace with statfs()

**Goal**: Test worker node with filesystem type spoofing

**Duration**: 15-30 minutes

**Prerequisites**:
- Experiment 05 concepts understood
- gcc installed
- Root access

**Steps**:

```bash
# 1. Build components
cd experiments/06-enhanced-ptrace-statfs
sudo ./run-enhanced-k3s.sh build

# Expected: "Interceptor built successfully"

# 2. Test interceptor with test program
sudo ./run-enhanced-k3s.sh test

# Expected: Should show filesystem type changing from 9p to ext4

# 3. Run k3s with enhanced interception
sudo ./run-enhanced-k3s.sh

# 4. Monitor in separate terminal
watch -n 5 'kubectl --insecure-skip-tls-verify get nodes'

# 5. Watch for interception messages
# Look for:
# [INTERCEPT-OPEN] /proc/sys/...
# [INTERCEPT-STATFS] Detected 9p filesystem, spoofing as ext4
```

**Data Collection**:

```bash
# Terminal 1: Run k3s
sudo ./run-enhanced-k3s.sh 2>&1 | tee /tmp/exp06-output.log

# Terminal 2: Monitor node status
while true; do
    echo "=== $(date) ==="
    kubectl --insecure-skip-tls-verify get nodes
    sleep 10
done | tee /tmp/exp06-node-status.log

# Terminal 3: Watch for errors
tail -f /tmp/k3s-ultimate/server/logs/kubelet.log | grep -i error
```

**Success Criteria**:
- ✅ kubelet starts without immediate crash
- ✅ Node registers as Ready
- ✅ Stability >60 seconds (improvement over Exp 04)
- ✅ "Filesystem type: 0xef53" in interception logs

**Metrics to Record**:
- Time until node Ready
- Duration node stays Ready
- Number of "unable to find data in memory cache" errors
- statfs() interception count

**Expected Outcomes**:

**Best Case** ✅:
- Node Ready for 10+ minutes
- Significantly reduced cAdvisor errors
- statfs() interceptions successful

**Realistic Case** ⚠️:
- Node Ready for 2-5 minutes
- Some cAdvisor errors reduced
- Stability improves over Exp 04

**Minimum Case** ❌:
- Same 30-60s as Exp 04
- No improvement
- Indicates additional issues beyond statfs()

### Experiment 07: FUSE cgroup Emulation

**Goal**: Test virtual cgroupfs filesystem

**Duration**: 20-30 minutes

**Prerequisites**:
- libfuse-dev installed: `sudo apt-get install libfuse-dev`
- gcc installed
- Root access

**Steps**:

**Phase 1: Component Testing**

```bash
cd experiments/07-fuse-cgroup-emulation

# 1. Build FUSE cgroupfs
sudo ./run-k3s-with-fuse-cgroups.sh build

# 2. Run component tests
sudo ./test_fuse.sh

# Expected: All tests should pass
# ✓ FUSE cgroupfs compiled
# ✓ FUSE filesystem mounted
# ✓ Subsystem directory exists
# ✓ Static file read correctly
# ✓ Dynamic file generated
# ... etc
```

**Phase 2: FUSE Mount Testing**

```bash
# 1. Test FUSE mount only
sudo ./run-k3s-with-fuse-cgroups.sh test-fuse

# 2. Verify filesystem
ls -la /tmp/fuse-cgroup/
# Should show: cpu, memory, cpuacct, blkio, etc.

# 3. Read cgroup files
cat /tmp/fuse-cgroup/cpu/cpu.shares
# Expected: 1024

cat /tmp/fuse-cgroup/memory/memory.usage_in_bytes
# Expected: Some reasonable number

# 4. Check filesystem type
stat -f /tmp/fuse-cgroup/
# Should show FUSE filesystem
```

**Phase 3: k3s Integration**

```bash
# 1. Start k3s with FUSE cgroups
sudo ./run-k3s-with-fuse-cgroups.sh

# 2. Monitor
# Watch for k3s detecting FUSE cgroup files
# Check if cAdvisor tries to access them
```

**Success Criteria**:
- ✅ FUSE filesystem mounts successfully
- ✅ All cgroup files readable
- ✅ Dynamic files return changing values
- ✅ k3s can access mounted filesystem

**Troubleshooting**:
```bash
# FUSE mount fails
sudo fusermount -u /tmp/fuse-cgroup  # Unmount if stuck
lsmod | grep fuse  # Check FUSE module loaded

# Files not readable
ls -la /tmp/fuse-cgroup/cpu/  # Check permissions
cat /tmp/fuse-cgroup/cpu/cpu.shares  # Direct test

# k3s not using FUSE cgroups
# This experiment may need ptrace redirection (see Exp 08)
```

### Experiment 08: Ultimate Hybrid

**Goal**: Combine ALL techniques for maximum stability

**Duration**: 60-120 minutes (includes long-running stability test)

**Prerequisites**:
- All components from Exp 05-07
- Sufficient time for 60+ minute test
- Multiple terminal windows

**Steps**:

**Phase 1: Component Verification**

```bash
cd experiments/08-ultimate-hybrid

# 1. Build all components
sudo ./run-ultimate-k3s.sh build

# Expected output:
# [INFO] Building enhanced ptrace interceptor...
# [SUCCESS] Ptrace interceptor built
# [INFO] Building FUSE cgroup emulator...
# [SUCCESS] FUSE cgroupfs built

# 2. Run component tests
sudo ./run-ultimate-k3s.sh test

# Should test:
# - FUSE mount/unmount
# - Ptrace interception
# - All components integrate
```

**Phase 2: Integration Test**

```bash
# Terminal 1: Start ultimate k3s
sudo ./run-ultimate-k3s.sh 2>&1 | tee /tmp/exp08-full.log

# Expected startup sequence:
# [Exp 05] Setting up fake CNI plugin...
# [Exp 04] Setting up fake /proc/sys files...
# [Exp 01] Setting up /dev/kmsg workaround...
# [Exp 02] Configuring mount propagation...
# [Exp 07] Mounting FUSE cgroup emulator...
# [Exp 06] Starting k3s with enhanced interceptor...

# Watch for:
# [INTERCEPT-OPEN] - File path redirection
# [INTERCEPT-STATFS] - Filesystem type spoofing
# [FUSE] - cgroup file access (if logged)
```

**Phase 3: Monitoring Setup**

```bash
# Terminal 2: Node status tracker
while true; do
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    STATUS=$(kubectl --insecure-skip-tls-verify get nodes 2>&1)
    echo "[$TIMESTAMP] $STATUS"
    sleep 30  # Check every 30 seconds
done | tee /tmp/exp08-nodes.log

# Terminal 3: Error monitor
tail -f /tmp/k3s-ultimate/server/logs/kubelet.log | \
    grep -iE "error|warn|cadvisor" | \
    tee /tmp/exp08-errors.log

# Terminal 4: Resource monitor
while true; do
    echo "=== $(date) ==="
    ps aux | grep -E "k3s|ptrace|fuse"
    free -h
    sleep 60
done | tee /tmp/exp08-resources.log
```

**Phase 4: Stability Test**

```bash
# Run for 60 minutes minimum
START_TIME=$(date +%s)
TARGET_DURATION=3600  # 60 minutes in seconds

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    MINUTES=$((ELAPSED / 60))

    if [ $ELAPSED -ge $TARGET_DURATION ]; then
        echo "✅ 60-minute stability test COMPLETE"
        break
    fi

    echo "=== Minute $MINUTES/60 ==="
    kubectl --insecure-skip-tls-verify get nodes -o wide

    sleep 60
done
```

**Success Criteria**:

**Minimum Success** ⚠️:
- [ ] k3s starts without fatal errors
- [ ] kubelet initializes
- [ ] Node registers (even if NotReady)
- [ ] Runs for >5 minutes

**Good Success** ✅:
- [ ] Node reaches Ready state
- [ ] Stability >10 minutes
- [ ] Fewer errors than Exp 04/06
- [ ] Some cgroup metrics working

**Complete Success** 🎉:
- [ ] Node stays Ready 60+ minutes
- [ ] Zero "unable to find data in memory cache" errors
- [ ] cAdvisor successfully collecting metrics
- [ ] Pods can be scheduled
- [ ] Stable resource usage

**Data Analysis**:

```bash
# After test completes, analyze logs

# 1. Count node Ready duration
grep "Ready" /tmp/exp08-nodes.log | wc -l
grep "NotReady" /tmp/exp08-nodes.log | wc -l

# 2. Error frequency
grep "unable to find data" /tmp/exp08-errors.log | wc -l

# 3. Interception statistics
grep "\[INTERCEPT-" /tmp/exp08-full.log | wc -l
grep "\[INTERCEPT-STATFS\]" /tmp/exp08-full.log | wc -l

# 4. Resource usage trend
grep "free" /tmp/exp08-resources.log | tail -20

# 5. Generate summary report
cat > /tmp/exp08-summary.txt << EOF
Experiment 08 Test Results
==========================
Start: $(head -1 /tmp/exp08-full.log | awk '{print $1, $2}')
End: $(tail -1 /tmp/exp08-full.log | awk '{print $1, $2}')

Node Ready count: $(grep -c "Ready" /tmp/exp08-nodes.log)
Node NotReady count: $(grep -c "NotReady" /tmp/exp08-nodes.log)
Total errors: $(wc -l < /tmp/exp08-errors.log)
cAdvisor errors: $(grep -c "unable to find data" /tmp/exp08-errors.log)

Interceptions:
  Total: $(grep -c "\[INTERCEPT-" /tmp/exp08-full.log)
  OPEN: $(grep -c "\[INTERCEPT-OPEN\]" /tmp/exp08-full.log)
  STATFS: $(grep -c "\[INTERCEPT-STATFS\]" /tmp/exp08-full.log)
EOF

cat /tmp/exp08-summary.txt
```

## Post-Test Actions

### If Successful (60+ min stability)

```bash
# 1. Document success
cat > SUCCESS_REPORT.md << EOF
# Worker Node Success Report

Date: $(date)
Experiment: 08 - Ultimate Hybrid
Duration: [X] minutes
Status: ✅ SUCCESS

## Results
- Node Ready: YES
- Duration: [X] minutes
- Errors: [count]
- Pods Scheduled: [YES/NO]

## Logs
- Full log: /tmp/exp08-full.log
- Node status: /tmp/exp08-nodes.log
- Errors: /tmp/exp08-errors.log

## Next Steps
- Package as production solution
- Add to SessionStart hook
- Submit upstream proposals with results
EOF

# 2. Create production script
# Clean up experimental scripts into single production-ready version

# 3. Engage upstream
# Open issues on k3s-io/k3s and google/cadvisor with success data
```

### If Partial Success (>5 min, <60 min)

```bash
# 1. Analyze what's working vs failing
diff /tmp/exp08-full.log /tmp/exp04-output.log  # Compare with Exp 04

# 2. Identify patterns
# Which errors still occur?
# Which interceptions are working?

# 3. Iterate
# Add more syscall interceptions?
# Enhance FUSE cgroup emulation?
# Try different k3s flags?
```

### If Failure (No improvement)

```bash
# 1. Deep dive analysis
# Extract exact failure point
grep -A 10 -B 10 "error" /tmp/exp08-errors.log | head -50

# 2. Consider alternatives
# - Custom kubelet build (docs/proposals/custom-kubelet-build.md)
# - Pure upstream approach (wait for cAdvisor 9p support)
# - External cluster for worker functionality

# 3. Document learnings
# What did we learn about the blocker?
# What can inform upstream proposals?
```

## Test Result Template

```markdown
# Test Results: Experiment [NUMBER]

**Date**: YYYY-MM-DD
**Duration**: X minutes
**Tester**: [Name/Environment]

## Environment
- OS: Linux X.X.X
- Filesystem: 9p
- k3s version: vX.XX.X
- Sandbox: gVisor/Cloud IDE/etc

## Results
- [ ] Component builds successfully
- [ ] Service starts
- [ ] Expected functionality works
- [ ] Stability achieved

## Metrics
- Startup time: X seconds
- Ready duration: X minutes
- Error count: X
- Resource usage: X MB RAM, X% CPU

## Observations
[Detailed notes on what happened]

## Logs
[Relevant log excerpts]

## Conclusion
[SUCCESS / PARTIAL / FAILURE]

## Next Steps
[What to do based on results]
```

## Quick Test Commands

For rapid iteration:

```bash
# Quick control-plane test (Exp 05)
cd solutions/control-plane-native && sudo ./start-k3s-native.sh

# Quick Exp 06 test (workers with ptrace)
cd experiments/06-enhanced-ptrace-statfs && sudo ./run-enhanced-k3s.sh

# Quick FUSE test (Exp 07)
cd experiments/07-fuse-cgroup-emulation && sudo ./test_fuse.sh

# Full integration (Exp 08)
cd experiments/08-ultimate-hybrid && sudo ./run-ultimate-k3s.sh
```

## Cleanup

After testing:

```bash
# Stop all k3s processes
sudo killall k3s

# Unmount FUSE filesystems
sudo fusermount -u /tmp/fuse-cgroup

# Clean up /dev/kmsg
sudo umount /dev/kmsg

# Remove temporary data
sudo rm -rf /tmp/k3s-*
sudo rm -rf /tmp/exp0*-*.log

# Archive results
mkdir -p test-results/$(date +%Y%m%d-%H%M%S)
mv /tmp/*.log test-results/$(date +%Y%m%d-%H%M%S)/
```

---

**Document Status**: Comprehensive testing guide
**Last Updated**: 2025-11-22
**Related**: All experiments (01-08), RESEARCH-CONTINUATION.md
