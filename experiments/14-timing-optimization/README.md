# Experiment 14: Timing Optimization

**Date**: 2025-11-22
**Status**: Testing - Attempting to resolve API server timing issue

## Problem Statement

Experiment 13 successfully resolved all 6 fundamental blockers, but encountered a timing issue:

```
PostStartHook "scheduling/bootstrap-system-priority-classes" failed:
unable to add default system priority classes:
priorityclasses.scheduling.k8s.io "system-node-critical" is forbidden:
not yet ready to handle request
```

The API server's post-start hooks are running before the API server is fully initialized to handle requests.

## Root Cause Analysis

The timing issue is caused by:
1. **Ptrace overhead**: Every syscall interception adds 2-5x latency
2. **Verbose output**: stderr contention from verbose logging
3. **Unnecessary interceptions**: Intercepting READ operations that don't need modification
4. **Initialization race**: Post-start hooks don't wait for API server readiness

## Hypothesis

By optimizing ptrace performance, we can reduce initialization time and allow the API server to become ready before post-start hooks execute.

## Optimizations Implemented

### 1. Write-Only Interception (50% reduction)

**Problem**: Experiment 13 intercepted ALL `/proc/sys/*` operations.

**Solution**: Only intercept WRITES.

**Old Code** (Exp 13):
```c
static int should_redirect(const char *path) {
    if (strstr(path, "/proc/sys/") != NULL)
        return 1;
    // Intercepts both reads and writes
}
```

**New Code** (Exp 14):
```c
static int should_redirect(const char *path, int flags) {
    int access_mode = flags & O_ACCMODE;
    int is_write = (access_mode == O_WRONLY || access_mode == O_RDWR);

    if (!is_write) {
        return 0; // Skip reads entirely
    }

    if (strstr(path, "/proc/sys/") != NULL)
        return 1;
}
```

**Impact**: ~50% reduction in intercepted syscalls (most are reads).

### 2. No Verbose Output

**Problem**: Verbose logging creates stderr contention.

**Solution**: Run without `-v` flag.

**Impact**: Eliminates fprintf() calls during interception.

### 3. Extended Initialization Wait

**Problem**: 60 seconds may not be enough with ptrace overhead.

**Solution**: Wait 90 seconds before checking status.

**Impact**: Gives API server more time to initialize.

### 4. Writable Fake Files

**Problem**: Write failures could cause errors.

**Solution**: Make all fake /proc/sys files world-writable (666).

**Impact**: Ensures writes succeed even if redirected.

## Expected Outcomes

### Best Case ✅
- k3s runs for 90+ seconds without exiting
- API server becomes Ready
- Post-start hooks complete successfully
- Node shows as Ready: `kubectl get nodes`
- Fully functional worker node achieved!

### Moderate Case ⚠️
- k3s runs longer than Experiment 13 (>20 seconds)
- Timing issue still present but delayed
- Proves optimization direction is correct
- Need further tuning

### Worst Case ❌
- No improvement over Experiment 13
- Timing issue persists
- Indicates deeper k3s initialization problem
- May need different approach (disable hooks, patch k3s)

## Performance Comparison

| Metric | Exp 13 | Exp 14 (Expected) |
|--------|--------|-------------------|
| Syscalls intercepted | 100% | ~50% (writes only) |
| Stderr output | High (verbose) | None |
| Initialization wait | 60s | 90s |
| Ptrace overhead | 2-5x | 1-3x (fewer interceptions) |

## Test Methodology

1. Clean environment (kill existing k3s)
2. Compile optimized interceptor
3. Create fake /proc/sys files (world-writable)
4. Start k3s with optimized ptrace (no verbose)
5. Wait 90 seconds
6. Check process status
7. Check for timing errors in logs
8. Attempt kubectl operations

## Success Criteria

**Minimum Success**:
- ✅ k3s runs >30 seconds (improvement over Exp 13)
- ✅ No crash from timing issue (graceful degradation)

**Target Success**:
- ✅ k3s runs 90+ seconds
- ✅ API server responds to kubectl
- ✅ No post-start hook errors

**Complete Success**:
- ✅ All of the above
- ✅ Node shows as Ready
- ✅ Can create/delete resources
- ✅ Fully functional worker node

## Alternative Approaches (if this fails)

1. **Disable post-start hooks**: Patch k3s to skip bootstrap hooks
2. **Increase hook timeouts**: Modify k3s source to wait longer
3. **Two-stage startup**: Start API server first, then enable hooks
4. **Use control-plane mode**: Revert to Experiment 05 (production-ready)

## Files

- `ptrace_interceptor_optimized.c` - Write-only interceptor
- `run-optimized-k3s.sh` - Optimized startup script
- `README.md` - This file
- `/tmp/exp14-k3s.log` - Runtime logs (created during execution)

## Usage

```bash
cd experiments/14-timing-optimization
bash run-optimized-k3s.sh

# Monitor in real-time
tail -f /tmp/exp14-k3s.log

# Check status after 90s
kubectl get nodes --insecure-skip-tls-verify
kubectl get pods -A --insecure-skip-tls-verify
```

## References

- **Experiment 13**: Resolved 6/6 blockers, timing issue discovered
- **Ptrace overhead**: 2-5x documented in Experiment 06
- **k3s initialization**: API server readiness is critical path
