# Experiment 6: Enhanced Ptrace with statfs() Interception for Worker Nodes

## Context

**Building on Experiment 05 breakthrough**: Experiment 05 achieved a fully functional control-plane using a fake CNI plugin. This experiment focuses on the remaining challenge: **enabling stable worker nodes**.

## Hypothesis

By intercepting the `statfs()` syscall in addition to `open()/openat()`, we can mask the 9p filesystem type and present it as ext4 to cAdvisor, potentially achieving stable worker node operation where Experiment 04 achieved only 30-60 seconds of stability.

## Background

**Experiment 04 Results**: Demonstrated that ptrace interception works for `/proc/sys` file access, enabling kubelet to start and register as Ready. However, kubelet becomes unstable after 30-60 seconds.

**Root Cause Analysis**: cAdvisor uses `statfs()` to detect filesystem types. Experiment 04's interceptor only modified file paths (open/openat), not filesystem metadata queries (statfs).

### The Problem

```c
// cAdvisor checks filesystem type using statfs()
struct statfs buf;
statfs("/", &buf);
if (buf.f_type == 0x01021997) {  // 9p magic number
    return error("unsupported filesystem");
}
```

The `statfs()` syscall returns immediately from the kernel with the real filesystem type. Experiment 04's interceptor only modified file paths, not syscall return values.

## Approach

### Enhanced Ptrace Strategy

1. **Intercept statfs() syscall entry** - Allow syscall to execute normally
2. **Wait for syscall exit** - Capture return values
3. **Modify f_type field** - Change 9p (0x01021997) to ext4 (0xEF53)
4. **Write modified buffer back** - Update tracee's memory
5. **Continue execution** - Process sees ext4 instead of 9p

### Technical Challenges

**Challenge 1: Syscall Exit Interception**
- Need to intercept both entry AND exit of statfs()
- Use PTRACE_SYSCALL twice per syscall
- First stop: syscall entry (can modify arguments)
- Second stop: syscall exit (can modify return values)

**Challenge 2: Memory Buffer Modification**
- statfs() takes a pointer to `struct statfs`
- Must read entire structure from tracee memory
- Modify f_type field
- Write structure back to tracee memory

**Challenge 3: Performance**
- statfs() is called frequently by cAdvisor
- Must minimize overhead to maintain stability
- Consider caching filesystem type responses

## Method

### Phase 1: statfs() Interception Proof of Concept

**Test Program** (`test_statfs.c`):
```c
#include <sys/vfs.h>
#include <stdio.h>

int main() {
    struct statfs buf;
    statfs("/", &buf);
    printf("Filesystem type: 0x%lx\n", buf.f_type);
    return 0;
}
```

**Expected Output (without interception)**:
```bash
$ ./test_statfs
Filesystem type: 0x01021997  # 9p
```

**Expected Output (with interception)**:
```bash
$ ./enhanced_interceptor ./test_statfs
Filesystem type: 0xef53  # ext4
```

### Phase 2: Enhanced Interceptor Implementation

**File**: `enhanced_ptrace_interceptor.c`

Key features:
- Track syscall entry vs exit state
- Intercept open(), openat(), statfs(), fstatfs()
- Modify both arguments (file paths) and return values (filesystem types)
- Handle multi-threaded processes
- Cache frequently accessed paths

### Phase 3: Integration with k3s

**Wrapper Script**: `run-enhanced-k3s.sh`

Combines:
- Fake /proc/sys files (from Experiment 04)
- Enhanced ptrace interceptor
- k3s with optimized flags

### Phase 4: Stability Testing

**Test Plan**:
1. Start k3s with enhanced interceptor
2. Monitor node status every 10 seconds
3. Run for 60 minutes minimum
4. Check for cAdvisor errors in logs
5. Attempt to schedule test pods

**Success Criteria**:
- ✅ Node remains Ready for 60+ minutes
- ✅ No "unable to find data in memory cache" errors
- ✅ cAdvisor reports filesystem statistics
- ✅ Pods can be scheduled (even if not running)

## Implementation

### Enhanced Interceptor Code

See `enhanced_ptrace_interceptor.c` for full implementation.

**Key Functions**:

```c
// Track syscall state
typedef enum {
    SYSCALL_ENTRY,
    SYSCALL_EXIT
} syscall_state_t;

// Intercept statfs() exit
void handle_statfs_exit(pid_t pid, struct user_regs_struct *regs) {
    // Read struct statfs from tracee memory
    struct statfs buf;
    unsigned long buffer_addr = regs->rsi;  // Second argument

    read_memory(pid, buffer_addr, &buf, sizeof(buf));

    // Check if filesystem is 9p
    if (buf.f_type == 0x01021997) {  // 9p
        printf("[INTERCEPT] statfs() returned 9p, changing to ext4\n");
        buf.f_type = 0xEF53;  // ext4
        write_memory(pid, buffer_addr, &buf, sizeof(buf));
    }
}

// Main interception loop
int main() {
    pid_t child = fork();
    if (child == 0) {
        ptrace(PTRACE_TRACEME);
        execv("/usr/local/bin/k3s", ...);
    }

    syscall_state_t state = SYSCALL_ENTRY;

    while (1) {
        ptrace(PTRACE_SYSCALL, child, 0, 0);
        wait(NULL);

        struct user_regs_struct regs;
        ptrace(PTRACE_GETREGS, child, 0, &regs);

        if (state == SYSCALL_ENTRY) {
            // Handle syscall entry (modify arguments)
            if (regs.orig_rax == SYS_open || regs.orig_rax == SYS_openat) {
                handle_open_entry(child, &regs);
            }
            state = SYSCALL_EXIT;
        } else {
            // Handle syscall exit (modify return values)
            if (regs.orig_rax == SYS_statfs || regs.orig_rax == SYS_fstatfs) {
                handle_statfs_exit(child, &regs);
            }
            state = SYSCALL_ENTRY;
        }
    }
}
```

## Results

### Initial Testing

```bash
$ gcc -o enhanced_ptrace_interceptor enhanced_ptrace_interceptor.c
$ ./run-enhanced-k3s.sh
```

**Expected Observations**:
1. Interception of /proc/sys paths (from Experiment 04)
2. NEW: Interception of statfs() calls
3. NEW: Filesystem type changes logged
4. k3s startup (same as before)
5. NEW: Sustained stability beyond 60 seconds?

### Comparison with Experiment 04

| Metric | Experiment 04 | Experiment 05 | Change |
|--------|---------------|---------------|--------|
| Initial startup | ✅ Success | ✅ Success | Same |
| Node registers | ✅ Yes | ✅ Yes | Same |
| Stability duration | ❌ 30-60s | ❓ Testing | TBD |
| cAdvisor errors | ❌ Frequent | ❓ Testing | TBD |
| Filesystem detection | ❌ 9p | ✅ ext4 (spoofed) | **Improved** |
| statfs() interception | ❌ No | ✅ Yes | **New** |

## Analysis

### What We Expect to Improve

1. **cAdvisor filesystem detection** - Should now see ext4
2. **Cache initialization** - Should succeed with spoofed filesystem type
3. **Stability duration** - Should extend beyond 60 seconds

### Remaining Challenges

Even with statfs() interception, we may still face:

1. **cgroup filesystem access** - Still requires /sys/fs/cgroup emulation
2. **Disk statistics** - statfs() also returns disk space info (blocks, inodes)
3. **Performance overhead** - More syscalls intercepted = more latency

### Potential Outcomes

**Outcome A: Full Success** ✅
- Node stays Ready indefinitely
- cAdvisor stops complaining
- Ready for Experiment 07 (integration)

**Outcome B: Partial Success** ⚠️
- Stability improves (60s → 10+ minutes)
- Fewer errors but still some issues
- Proceed to Experiment 06 (cgroup emulation)

**Outcome C: No Improvement** ❌
- Same 30-60s failure
- Indicates cAdvisor checks more than just statfs()
- Need deeper analysis of cAdvisor source

## Next Steps

Based on results:

1. **If successful** → Document as production-ready solution
2. **If partial** → Combine with Experiment 06 (FUSE cgroups)
3. **If unsuccessful** → Investigate additional syscalls to intercept

## Files

- `README.md` - This document
- `enhanced_ptrace_interceptor.c` - Enhanced interceptor source
- `run-enhanced-k3s.sh` - Wrapper script
- `test_statfs.c` - Test program for validation
- `results.md` - Test results and measurements

## References

- statfs(2) man page: https://man7.org/linux/man-pages/man2/statfs.2.html
- Linux filesystem magic numbers: `/usr/include/linux/magic.h`
- Ptrace syscall exit handling: https://stackoverflow.com/questions/7665309/
- cAdvisor fs detection: https://github.com/google/cadvisor/blob/master/fs/fs.go
