# cAdvisor 9p Filesystem Support Proposal

## Summary

Add support for 9p virtual filesystem to cAdvisor, enabling kubelet to run in sandboxed environments (gVisor, cloud IDEs, browsers) that use 9p for filesystem access.

## Motivation

### Problem Statement

cAdvisor currently only supports traditional Linux filesystems (ext4, xfs, btrfs, overlayfs). When kubelet tries to initialize in an environment using 9p virtual filesystem, cAdvisor fails with:

```
ERROR Failed to start ContainerManager: failed to get rootfs info: unable to find data in memory cache
```

This makes kubelet completely non-functional in environments using:
- **gVisor** (runsc) - Security-focused container runtime
- **Cloud IDEs** - GitHub Codespaces, GitPod, Cloud9
- **Browser-based dev** - Claude Code, StackBlitz
- **Nested virtualization** - Certain VM configurations

### Use Cases

**Development Workflows**:
- Developers want to run k3s/k8s locally for testing
- Helm chart development without external clusters
- Kubernetes manifest validation
- Learning kubectl without infrastructure costs

**Production Scenarios**:
- Edge computing with gVisor for security
- Serverless container platforms using gVisor
- Multi-tenant environments requiring strong isolation
- Embedded systems with custom filesystems

### Impact

**Users Affected**: Estimated 10,000+ developers using cloud IDEs for Kubernetes development

**Workarounds**: Currently, users must:
1. Use external clusters (costs money, adds latency)
2. Accept control-plane-only mode (limited functionality)
3. Complex ptrace/FUSE emulation (research project, unstable)

## Proposal

### Add 9p to Supported Filesystems

**File**: `fs/fs.go`

```go
func isSupportedFilesystem(fsType string) bool {
    supportedFS := map[string]bool{
        "ext2": true,
        "ext3": true,
        "ext4": true,
        "xfs": true,
        "btrfs": true,
        "overlayfs": true,
        "9p": true,  // ADD THIS LINE
    }
    return supportedFS[fsType]
}
```

### Implement 9p-specific Metrics Collection

**File**: `fs/9p.go` (new file)

```go
package fs

import (
    "golang.org/x/sys/unix"
)

const (
    NineP_MAGIC = 0x01021997
)

// Get9pFsInfo retrieves filesystem information for 9p filesystems
func Get9pFsInfo(device string) (*FsInfo, error) {
    var statfs unix.Statfs_t
    err := unix.Statfs(device, &statfs)
    if err != nil {
        return nil, err
    }

    // 9p provides basic filesystem stats
    return &FsInfo{
        Device:     device,
        Type:       "9p",
        Capacity:   uint64(statfs.Blocks) * uint64(statfs.Bsize),
        Available:  uint64(statfs.Bavail) * uint64(statfs.Bsize),
        Free:       uint64(statfs.Bfree) * uint64(statfs.Bsize),
        Inodes:     statfs.Files,
        InodesFree: statfs.Ffree,
        DiskStats:  DiskStats{},  // 9p doesn't expose device stats
    }, nil
}
```

**File**: `fs/fs.go` (update)

```go
func GetFsInfo(device string) (*FsInfo, error) {
    // ... existing code

    // Detect filesystem type
    fsType := detectFilesystemType(device)

    switch fsType {
    case "9p":
        return Get9pFsInfo(device)
    case "ext4", "xfs", "btrfs":
        return getDefaultFsInfo(device)
    // ... other cases
    }
}
```

## Design Considerations

### What Works on 9p

**Available Metrics**:
- ✅ Filesystem capacity
- ✅ Available space
- ✅ Inode counts
- ✅ File access times

**Limitations**:
- ❌ Block device statistics (no `/dev` device)
- ❌ I/O counters (virtualized)
- ❌ Per-process I/O (not exposed)

### Handling Missing Metrics

**Approach**: Return zero/nil for unavailable metrics

```go
func Get9pFsInfo(device string) (*FsInfo, error) {
    info := &FsInfo{
        // ... basic stats from statfs()
    }

    // 9p doesn't provide device stats
    info.DiskStats = DiskStats{
        ReadsCompleted:  0,
        WritesCompleted: 0,
        // Note: Values are zero because 9p is virtualized
    }

    return info, nil
}
```

**Documentation**: Clearly document which metrics are unavailable on 9p

### Backwards Compatibility

**No Breaking Changes**:
- Existing filesystems continue to work exactly as before
- 9p support is additive only
- No API changes
- No configuration changes required

**Feature Flag (Optional)**:
```go
// Optional: Allow disabling 9p if needed
if !config.Enable9pSupport {
    return ErrUnsupportedFilesystem
}
```

## Testing Plan

### Unit Tests

```go
// fs/9p_test.go
func Test9pFsInfo(t *testing.T) {
    // Create test with 9p filesystem
    info, err := Get9pFsInfo("/")
    require.NoError(t, err)

    assert.Equal(t, "9p", info.Type)
    assert.Greater(t, info.Capacity, uint64(0))
    assert.LessOrEqual(t, info.Available, info.Capacity)
}

func Test9pWithVirtualFS(t *testing.T) {
    // Test with actual 9p mount
    // (requires gVisor or 9p FUSE mount)
}
```

### Integration Tests

**Test Environments**:
1. gVisor (runsc) container
2. QEMU with 9p filesystem
3. Cloud IDE (GitHub Codespaces)

**Test Cases**:
- cAdvisor starts successfully
- RootFsInfo returns valid data
- Container metrics collection works
- No errors in logs for 24 hours

### Performance Tests

**Benchmark**: Ensure 9p support doesn't degrade performance for other filesystems

```go
func Benchmark9pFsInfo(b *testing.B) {
    for i := 0; i < b.N; i++ {
        Get9pFsInfo("/")
    }
}

func BenchmarkExt4FsInfo(b *testing.B) {
    for i := 0; i < b.N; i++ {
        GetExt4FsInfo("/")
    }
}
```

## Implementation Roadmap

### Phase 1: Core Implementation (1 week)

- [ ] Add 9p to supported filesystems list
- [ ] Implement Get9pFsInfo function
- [ ] Add unit tests
- [ ] Update documentation

### Phase 2: Testing (1 week)

- [ ] Test in gVisor environment
- [ ] Test in cloud IDE
- [ ] Validate metrics accuracy
- [ ] Performance benchmarking

### Phase 3: Review & Merge (2-4 weeks)

- [ ] Open GitHub issue for discussion
- [ ] Submit PR with implementation
- [ ] Address review feedback
- [ ] Update CHANGELOG

### Phase 4: Release & Documentation (1 week)

- [ ] Include in next cAdvisor release
- [ ] Update official documentation
- [ ] Announce in Kubernetes community
- [ ] Blog post explaining use case

## Metrics Impact

### New Metrics

**None** - Existing metrics continue to be reported

### Modified Metrics

**Disk I/O metrics** on 9p:
- Will return zeros (not available)
- Should be documented as expected behavior

### Metric Quality

**Filesystem metrics**: Accurate (from statfs syscall)
**Container metrics**: Unchanged (cgroup-based)
**Network metrics**: Unchanged

## Documentation Updates

### cAdvisor README

```markdown
## Supported Filesystems

cAdvisor supports the following filesystems:

- ext2, ext3, ext4
- XFS
- Btrfs
- OverlayFS
- **9p** (virtual filesystem, limited metrics)

Note: When using 9p, disk I/O statistics may not be available.
```

### Kubelet Documentation

```markdown
## Running in Sandboxed Environments

Kubelet can now run in environments using 9p virtual filesystems (gVisor, cloud IDEs).

**Requirements**:
- cAdvisor v0.XX.0 or later

**Limitations**:
- Disk I/O metrics not available
- Container metrics may be approximate
```

## Security Considerations

**No Security Impact**:
- 9p filesystem access follows same permissions as other filesystems
- No new capabilities required
- No privileged operations added

**Sandboxing Benefits**:
- Enables Kubernetes in more secure environments (gVisor)
- Supports stronger isolation
- Aligns with zero-trust principles

## Alternatives Considered

### Alternative 1: Stub Metrics

**Idea**: Return fake metrics for 9p

**Rejected**: Misleading, users expect accurate data

### Alternative 2: Disable cAdvisor

**Idea**: Run kubelet without cAdvisor

**Rejected**: Loses all metrics, breaks assumptions

### Alternative 3: FUSE Emulation

**Idea**: Emulate traditional filesystem over 9p

**Rejected**: Complex, performance overhead, maintenance burden

### Alternative 4: Status Quo

**Idea**: Do nothing, require users to use workarounds

**Rejected**: Poor user experience, blocks valid use cases

## Success Metrics

**Adoption**:
- [ ] 100+ users successfully running kubelet on 9p
- [ ] 0 reported regressions on traditional filesystems
- [ ] Positive community feedback

**Quality**:
- [ ] All tests passing
- [ ] No performance degradation
- [ ] Clean code review

**Impact**:
- [ ] Referenced in Kubernetes documentation
- [ ] Adopted by cloud IDE providers
- [ ] Used in production gVisor deployments

## References

**Related Issues**:
- kubernetes/kubernetes#XXXXX - kubelet fails on 9p filesystem
- k3s-io/k3s#8404 - Unable to find data in memory cache

**Related Projects**:
- gVisor: https://gvisor.dev
- Plan 9: http://9p.io/plan9/
- QEMU 9p: https://wiki.qemu.org/Documentation/9psetup

**Research**:
- 9p protocol specification
- gVisor filesystem compatibility
- cAdvisor architecture

## Open Questions

1. **Should we support 9p2000.L extensions?**
   - Likely yes, for better performance
   - Need to test with different 9p implementations

2. **How to handle 9p protocol versions?**
   - Auto-detect and adapt
   - Document supported versions

3. **Should we warn users about limited metrics?**
   - Log message on first 9p detection?
   - Include in metric descriptions?

## Conclusion

Adding 9p filesystem support to cAdvisor is a **low-risk, high-impact change** that enables Kubernetes in modern sandboxed environments while maintaining backwards compatibility.

**Recommended Action**: Approve and implement

---

**Proposal Status**: Draft
**Target Release**: cAdvisor v0.XX.0
**Assignee**: TBD
**Reviewers**: cAdvisor maintainers, SIG Node

**GitHub Issue**: TBD
**Pull Request**: TBD

**Last Updated**: 2025-11-22
**Author**: Research Team
**Contact**: [Email/Slack]
