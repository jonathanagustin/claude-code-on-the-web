# Experiment 26: Namespace Isolation Testing

## Hypothesis

After Experiment 25 proved containers CAN run in gVisor, test which specific namespace or configuration triggers the blocker.

## Method

Progressive testing - add namespaces incrementally:
1. Minimal (pid, ipc, uts, mount)
2. Add network namespace
3. Add user namespace
4. Add cgroup namespace ← Test suspected blocker
5. Add capabilities configuration
6. Full k3s-like configuration

## Results

### 🎯 Blocker Identified: Cgroup Namespace

| Test | Configuration | Result | Error |
|------|--------------|---------|-------|
| 1 | Minimal namespaces | ✅ PASS | None |
| 2 | + network namespace | ✅ PASS | None |
| 3 | + user namespace | ✅ PASS | None |
| **4** | **+ cgroup namespace** | **❌ FAIL** | **cgroup namespaces aren't enabled in the kernel** |
| 5 | Capabilities only | ✅ PASS | None |
| 6 | Full k3s config | ❌ FAIL | cgroup namespaces error |
| 7 | Capabilities + cgroup | ❌ FAIL | cgroup namespaces error |

**Root Cause:** gVisor kernel doesn't support cgroup namespaces

### Solution Tested: runc Wrapper

Created `runc-gvisor-wrapper.sh` that:
1. Strips cgroup namespace from OCI spec using jq
2. Applies LD_PRELOAD for /proc/sys/* redirection
3. Executes real runc with modified spec

**Manual Test:** ✅ **SUCCESS**
```bash
$ /usr/bin/runc-gvisor run wrapper-test
SUCCESS: Wrapper stripped cgroup namespace!
```

**k3s Integration:** ⚠️ **PARTIAL SUCCESS**

Progress made:
- ✅ Cgroup namespace successfully stripped (no more "cgroup namespaces aren't enabled" error)
- ❌ Still blocked by cap_last_cap in runc init subprocess

The wrapper approach successfully solved the cgroup namespace issue but revealed the second blocker: LD_PRELOAD doesn't propagate to the runc init subprocess (confirmed from Experiment 24).

## Key Findings

### Two Separate Blockers

**Blocker 1: Cgroup Namespace** ✅ **SOLVED**
- gVisor kernel doesn't support cgroup namespaces
- Solution: Strip from OCI spec before execution
- Status: Working with runc-gvisor wrapper

**Blocker 2: cap_last_cap Access** ❌ **UNSOLVED**
- runc init subprocess requires `/proc/sys/kernel/cap_last_cap`
- LD_PRELOAD doesn't propagate to subprocess (Experiment 24)
- Solution needed: Patch runc to not require this file

### Process Flow

```
containerd
  ↓
  generates OCI spec WITH cgroup namespace
  ↓
runc-gvisor wrapper
  ↓
  strips cgroup namespace from spec ✅
  sets LD_PRELOAD for parent process ✅
  ↓
runc (parent process)
  ↓
  LD_PRELOAD works here ✅
  ↓
  ═══════ ISOLATION BOUNDARY ═══════
  ↓
runc init (subprocess)
  ↓
  Fresh environment - no LD_PRELOAD ❌
  Requires /proc/sys/kernel/cap_last_cap ❌
  FAILS
```

## Errors from k3s Integration

```
E1124 07:04:07.368733   50259 pod_workers.go:1324] "Error syncing pod, skipping"
err="failed to \"CreatePodSandbox\" for \"test-wrapper_default(...)\" with
CreatePodSandboxError: \"Failed to create sandbox for pod: rpc error: code = Unknown
desc = failed to start sandbox: failed to create containerd task: failed to create
shim task: OCI runtime create failed: runc create failed: unable to start container
process: error during container init: open /proc/sys/kernel/cap_last_cap: no such
file or directory\""
```

Note: No longer seeing "cgroup namespaces aren't enabled" - the wrapper successfully stripped it!

## Comparison with Previous Experiments

| Experiment | Finding | Status |
|------------|---------|--------|
| 24 | LD_PRELOAD doesn't reach runc init subprocess | Confirmed fundamental limitation |
| 25 | Containers work with minimal config | Proved concept possible |
| **26** | **Cgroup namespace is the trigger** | **Wrapper strips it successfully** |
| **26** | **cap_last_cap still blocks** | **Requires runc patching** |

## Next Steps

### Immediate: Experiment 27 - Patch runc

Since the wrapper approach solved one blocker but can't solve the second, we need to patch runc itself:

**Option 1: Skip cap_last_cap check**
```go
// In runc source: libcontainer/capabilities_linux.go
// Change getCapabilities() to return hardcoded value instead of reading file
func getCapabilities() (uint64, error) {
    // Original: read from /proc/sys/kernel/cap_last_cap
    // For gVisor: return hardcoded CAP_LAST_CAP (40)
    return 40, nil
}
```

**Option 2: Make cap_last_cap optional**
```go
// Fallback to default if file doesn't exist
func getCapabilities() (uint64, error) {
    val, err := readCapLastCap()
    if os.IsNotExist(err) {
        return 40, nil // Default for Linux 5.x+
    }
    return val, err
}
```

### Future: Alternative Runtimes

Test if other runtimes have different requirements:
- **youki** (Rust-based OCI runtime)
- **crun** with custom config
- **gVisor's runsc** as inner runtime (nested)

## Files Created

```
experiments/26-namespace-isolation-testing/
├── README.md                              # This file
├── test-progressive-namespaces.sh        # Namespace progression tests
├── config-no-cgroup-ns.toml              # Attempted containerd config
├── runc-gvisor-wrapper.sh                # Working wrapper (solves cgroup issue)
└── test-wrapper-solution.sh              # Integration test with k3s

/usr/bin/runc-gvisor                       # Installed wrapper
/tmp/wrapper-test/                         # Manual test artifacts (SUCCESS)
/tmp/namespace-tests/                      # Progressive test artifacts
/tmp/namespace-test-results.txt            # Test results summary
```

## Commands to Reproduce

### Progressive Namespace Tests
```bash
bash experiments/26-namespace-isolation-testing/test-progressive-namespaces.sh
# Shows: cgroup namespace triggers "cgroup namespaces aren't enabled" error
```

### Wrapper Manual Test
```bash
bash experiments/26-namespace-isolation-testing/test-wrapper-solution.sh
# Manual test: SUCCESS
# k3s integration: Partial (cgroup solved, cap_last_cap remains)
```

## Status

**Progress Made:**
- ✅ Identified exact blocker: cgroup namespace
- ✅ Created working wrapper solution
- ✅ Successfully strips cgroup namespace from specs
- ✅ Eliminated "cgroup namespaces aren't enabled" error

**Remaining Work:**
- ❌ cap_last_cap subprocess isolation (requires runc patching)
- Next: Experiment 27 - Build and test patched runc

## Conclusions

1. **Cgroup namespace blocker: SOLVED** - Wrapper successfully strips it
2. **cap_last_cap blocker: IDENTIFIED** - Requires runc source modification
3. **Wrapper approach: VIABLE** - Works for configuration-level changes
4. **Subprocess isolation: CONFIRMED** - LD_PRELOAD approach insufficient
5. **Path forward: CLEAR** - Patch runc to handle missing cap_last_cap file

This experiment proved the multi-layered nature of the problem and provided a working solution for the first layer. The second layer requires deeper intervention at the runc source code level.
