# Experiment 7: FUSE-based cgroup Filesystem Emulation

## Context

**Building on previous experiments:**
- ✅ **Experiment 05**: Control-plane with fake CNI plugin (SOLVED)
- ⚠️ **Experiment 04**: Worker nodes with ptrace (30-60s stability)
- 🔧 **Experiment 06**: Enhanced ptrace with statfs() interception (testing)

## Hypothesis

cAdvisor requires access to cgroup pseudo-files in `/sys/fs/cgroup/*` to collect container metrics. By creating a FUSE filesystem that emulates these cgroup files with realistic data, we can satisfy cAdvisor's requirements and achieve stable worker node operation.

## Background

### The cgroup Problem

cAdvisor needs to read cgroup files for container monitoring:

```bash
# cAdvisor reads these files:
/sys/fs/cgroup/cpu/cpu.shares
/sys/fs/cgroup/memory/memory.limit_in_bytes
/sys/fs/cgroup/memory/memory.usage_in_bytes
/sys/fs/cgroup/cpuacct/cpuacct.usage
# ... and many more
```

**Current Issues:**
1. These files don't exist or are read-only in gVisor sandbox
2. Creating fake regular files doesn't work (cAdvisor validates they're cgroup files)
3. cgroup files are special pseudo-files backed by the kernel
4. Ptrace can't intercept all the operations cAdvisor needs

### Why FUSE?

**FUSE (Filesystem in Userspace)** allows us to:
- Create a virtual filesystem that behaves like cgroupfs
- Return appropriate data for cgroup queries
- Handle cAdvisor's filesystem operations correctly
- Run in userspace (no kernel modules needed)

## Approach

### FUSE cgroup Emulator Design

```
┌─────────────┐
│   cAdvisor  │
└──────┬──────┘
       │ read("/sys/fs/cgroup/cpu/cpu.shares")
       ↓
┌──────────────────┐
│  FUSE cgroupfs   │  ← Our emulator
│  (userspace)     │
└──────┬───────────┘
       │ returns realistic data
       ↓
┌──────────────────┐
│  cAdvisor cache  │
└──────────────────┘
```

### Implementation Strategy

**Phase 1: Minimal FUSE Implementation**
- Mount FUSE filesystem at `/tmp/fuse-cgroup`
- Emulate basic directory structure
- Return static values for common cgroup files

**Phase 2: Realistic Data**
- Read actual system metrics where possible
- Calculate reasonable estimates for unavailable data
- Maintain consistency across reads

**Phase 3: Integration**
- Bind-mount `/tmp/fuse-cgroup` to `/sys/fs/cgroup`
- Or use ptrace to redirect cgroup paths
- Combine with Experiment 06 (statfs interception)

## Method

### Phase 1: Basic FUSE cgroup Emulator

**File**: `fuse_cgroupfs.c`

Key components:

```c
// FUSE operations we need to implement
static struct fuse_operations cgroupfs_ops = {
    .getattr    = cgroupfs_getattr,    // stat() on files
    .readdir    = cgroupfs_readdir,    // ls directory
    .open       = cgroupfs_open,       // open() file
    .read       = cgroupfs_read,       // read() file contents
    .statfs     = cgroupfs_statfs,     // statfs() on filesystem
};

// Return cgroupfs magic number
static int cgroupfs_statfs(const char *path, struct statvfs *stbuf) {
    stbuf->f_type = CGROUP_SUPER_MAGIC;  // 0x27e0eb
    stbuf->f_bsize = 4096;
    return 0;
}

// Return file attributes
static int cgroupfs_getattr(const char *path, struct stat *stbuf) {
    if (strcmp(path, "/") == 0) {
        // Root directory
        stbuf->st_mode = S_IFDIR | 0755;
        stbuf->st_nlink = 2;
        return 0;
    }

    if (strcmp(path, "/cpu") == 0 || strcmp(path, "/memory") == 0) {
        // Subsystem directories
        stbuf->st_mode = S_IFDIR | 0755;
        stbuf->st_nlink = 2;
        return 0;
    }

    if (strcmp(path, "/cpu/cpu.shares") == 0) {
        // Cgroup file
        stbuf->st_mode = S_IFREG | 0644;
        stbuf->st_nlink = 1;
        stbuf->st_size = 16;  // "1024\n"
        return 0;
    }

    return -ENOENT;
}

// Read file contents
static int cgroupfs_read(const char *path, char *buf, size_t size,
                         off_t offset, struct fuse_file_info *fi) {
    if (strcmp(path, "/cpu/cpu.shares") == 0) {
        const char *data = "1024\n";
        size_t len = strlen(data);
        if (offset < len) {
            if (offset + size > len)
                size = len - offset;
            memcpy(buf, data + offset, size);
            return size;
        }
        return 0;
    }

    return -ENOENT;
}
```

### Phase 2: Cgroup Files to Emulate

**Priority cgroup files** (based on cAdvisor source):

```bash
# CPU subsystem
/sys/fs/cgroup/cpu/cpu.shares         # 1024
/sys/fs/cgroup/cpu/cpu.cfs_period_us  # 100000
/sys/fs/cgroup/cpu/cpu.cfs_quota_us   # -1 (unlimited)
/sys/fs/cgroup/cpu/cpu.stat            # throttled_time 0

# CPU accounting
/sys/fs/cgroup/cpuacct/cpuacct.usage  # nanoseconds
/sys/fs/cgroup/cpuacct/cpuacct.stat   # user/system time

# Memory
/sys/fs/cgroup/memory/memory.limit_in_bytes      # large number
/sys/fs/cgroup/memory/memory.usage_in_bytes      # current usage
/sys/fs/cgroup/memory/memory.stat                # detailed stats
/sys/fs/cgroup/memory/memory.max_usage_in_bytes  # peak usage

# Block I/O
/sys/fs/cgroup/blkio/blkio.throttle.io_service_bytes  # I/O stats
```

### Phase 3: Mounting Strategy

**Option A: Bind Mount** (requires unmounting existing /sys/fs/cgroup)
```bash
# Mount FUSE filesystem
./fuse_cgroupfs /tmp/fuse-cgroup

# Bind mount over real cgroup
mount --bind /tmp/fuse-cgroup /sys/fs/cgroup
```

**Option B: Ptrace Redirection** (safer, works with Experiment 06)
```bash
# Mount FUSE at custom location
./fuse_cgroupfs /tmp/fuse-cgroup

# Use ptrace to redirect /sys/fs/cgroup → /tmp/fuse-cgroup
# (extend enhanced_ptrace_interceptor.c from Exp 06)
```

## Implementation

### Minimal FUSE Emulator

See `fuse_cgroupfs.c` for full implementation.

**Build requirements:**
```bash
apt-get install libfuse-dev
gcc -Wall fuse_cgroupfs.c -o fuse_cgroupfs `pkg-config fuse --cflags --libs`
```

**Usage:**
```bash
# Create mount point
mkdir -p /tmp/fuse-cgroup

# Mount FUSE filesystem
./fuse_cgroupfs /tmp/fuse-cgroup

# Verify it works
stat /tmp/fuse-cgroup
cat /tmp/fuse-cgroup/cpu/cpu.shares

# Unmount
fusermount -u /tmp/fuse-cgroup
```

### Integration Script

**File**: `run-k3s-with-fuse-cgroups.sh`

Combines:
1. FUSE cgroup emulator
2. Enhanced ptrace interceptor (from Exp 06)
3. Fake CNI plugin (from Exp 05)
4. All previous workarounds

## Expected Results

### Success Criteria

**Minimum Success** ⚠️:
- ✅ FUSE filesystem mounts successfully
- ✅ cAdvisor can read emulated cgroup files
- ✅ kubelet starts without errors
- ✅ Stability >60 seconds

**Full Success** ✅:
- ✅ Node registers and stays Ready
- ✅ Stability >60 minutes
- ✅ Pods can be scheduled
- ✅ No cAdvisor errors in logs

### Potential Issues

1. **FUSE availability in gVisor**
   - gVisor may restrict FUSE mounts
   - Fallback: Use ptrace redirection instead

2. **Cgroup file validation**
   - cAdvisor may validate file metadata deeply
   - Need correct st_mode, st_dev, etc.

3. **Dynamic data requirements**
   - Some cgroup files need changing values
   - May need to track time, calculate usage

4. **Performance overhead**
   - FUSE operations are userspace
   - Should be minimal for infrequent reads

## Comparison with Previous Approaches

| Approach | Filesystem Fix | Cgroup Fix | Expected Stability |
|----------|----------------|------------|-------------------|
| **Exp 04** | ❌ No | ⚠️ Partial (ptrace /proc/sys) | 30-60s |
| **Exp 06** | ✅ statfs() spoofing | ⚠️ Partial | TBD |
| **Exp 07** | ✅ statfs() spoofing | ✅ FUSE emulation | 60+ min? |

## Advantages of FUSE Approach

1. **Complete control** - We define all filesystem operations
2. **Kernel-like behavior** - Appears as real filesystem to applications
3. **No ptrace overhead** - Direct filesystem access
4. **Maintainable** - Easier to debug than ptrace interception
5. **Extensible** - Can add more cgroup files as needed

## Limitations

1. **Not real cgroups** - No actual resource management
2. **Fake metrics** - Container stats won't be accurate
3. **Development only** - Not suitable for production
4. **FUSE dependency** - Requires FUSE support in environment

## Testing Plan

### Test 1: FUSE Mount
```bash
./fuse_cgroupfs /tmp/fuse-cgroup
ls -la /tmp/fuse-cgroup
cat /tmp/fuse-cgroup/cpu/cpu.shares
```

**Expected**: Files readable, correct permissions

### Test 2: cAdvisor Compatibility
```bash
# Use cAdvisor's test tools
go test github.com/google/cadvisor/fs
```

**Expected**: Tests pass with FUSE filesystem

### Test 3: k3s Integration
```bash
# Mount FUSE cgroups
./fuse_cgroupfs /tmp/fuse-cgroup

# Redirect with ptrace OR bind-mount
# Then start k3s with Exp 06 interceptor
```

**Expected**: kubelet starts, node Ready, stable >60 min

## Next Steps

Based on results:

1. **If successful** → Document as production-ready solution
2. **If partial success** → Combine with Experiment 08 (all techniques)
3. **If FUSE blocked** → Fall back to pure ptrace approach
4. **If data validation issues** → Enhance emulated file realism

## Files

- `README.md` - This document
- `fuse_cgroupfs.c` - FUSE filesystem implementation
- `run-k3s-with-fuse-cgroups.sh` - Integration script
- `test_fuse.sh` - FUSE testing script
- `results.md` - Test results and findings

## References

- FUSE API: https://libfuse.github.io/doxygen/
- cgroup v1 documentation: https://www.kernel.org/doc/Documentation/cgroup-v1/
- cAdvisor cgroup code: https://github.com/google/cadvisor/tree/master/container/libcontainer
- FUSE filesystem magic numbers: `/usr/include/linux/magic.h`

## Conclusion

FUSE-based cgroup emulation represents a clean, maintainable solution to the cgroup access problem. Combined with Experiment 06's statfs() interception, this approach has high potential for achieving stable worker nodes in sandboxed environments.

**Key Innovation**: Emulate kernel cgroup pseudo-filesystem in userspace using FUSE

**Expected Impact**: Enable stable worker nodes with accurate cgroup file access
