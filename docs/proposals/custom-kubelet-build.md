# Custom Kubelet Build Without cAdvisor Dependency

## Overview

This document outlines the requirements and approach for building a custom version of kubelet that doesn't strictly require cAdvisor, enabling it to run in highly restricted sandbox environments where cAdvisor's filesystem requirements cannot be met.

## Background

### The Problem

cAdvisor (Container Advisor) is embedded in kubelet to collect container metrics. However, cAdvisor has hardcoded filesystem type requirements:

```go
// google/cadvisor/fs/fs.go
func isSupportedFilesystem(fsType string) bool {
    supportedFS := map[string]bool{
        "ext2": true,
        "ext3": true,
        "ext4": true,
        "xfs": true,
        "btrfs": true,
        "overlayfs": true,
        // 9p NOT supported!
    }
    return supportedFS[fsType]
}
```

In sandboxed environments using 9p virtual filesystems (gVisor, some cloud IDEs), this causes kubelet to fail immediately.

### Current Impact

- ❌ Worker nodes cannot start in gVisor sandboxes
- ❌ Developers cannot run full k3s locally
- ❌ Testing requires external clusters
- ❌ "Works on my machine" problems persist

## Proposed Solution

### Option 1: Make cAdvisor Optional

**Modification**: Add a kubelet flag to disable cAdvisor entirely

```go
// pkg/kubelet/kubelet.go

type KubeletConfiguration struct {
    // ... existing fields
    DisableCAdvisor bool `json:"disableCAdvisor,omitempty"`
}

func NewMainKubelet(...) (*Kubelet, error) {
    // ... existing code

    if !kubeletConfig.DisableCAdvisor {
        // Initialize cAdvisor (existing code)
        cadvisorInterface = cadvisor.New(...)
    } else {
        // Use stub implementation
        cadvisorInterface = &stubCAdvisor{}
    }

    // ... rest of initialization
}
```

**Usage**:
```bash
k3s server \
    --kubelet-arg="--disable-cadvisor=true"
```

**Pros**:
- ✅ Minimal code changes
- ✅ Backwards compatible
- ✅ Clear opt-in behavior

**Cons**:
- ❌ Loses all container metrics
- ❌ Monitoring/observability impacted
- ❌ May break assumptions in controllers

### Option 2: Stub cAdvisor Implementation

**Modification**: Provide a stub cAdvisor that returns fake/minimal metrics

```go
// pkg/kubelet/cadvisor/stub_cadvisor.go

package cadvisor

import (
    cadvisorapi "github.com/google/cadvisor/info/v1"
)

type StubCAdvisor struct{}

func (s *StubCAdvisor) Start() error {
    return nil // No-op
}

func (s *StubCAdvisor) GetRootFsInfo() (*cadvisorapi.FsInfo, error) {
    // Return minimal valid response
    return &cadvisorapi.FsInfo{
        Capacity:  1000000000000, // 1TB
        Available: 500000000000,   // 500GB
        Usage:     500000000000,   // 500GB
        Device:    "/dev/null",
    }, nil
}

func (s *StubCAdvisor) GetContainerInfo(name string, req *cadvisorapi.ContainerInfoRequest) (*cadvisorapi.ContainerInfo, error) {
    // Return minimal container info
    return &cadvisorapi.ContainerInfo{
        Spec: cadvisorapi.ContainerSpec{
            HasCpu:    false,
            HasMemory: false,
        },
        Stats: []*cadvisorapi.ContainerStats{},
    }, nil
}

// ... implement other required methods
```

**Usage**: Automatic fallback when cAdvisor initialization fails

**Pros**:
- ✅ Maintains interface compatibility
- ✅ Kubelet can still function
- ✅ Some basic metrics available

**Cons**:
- ❌ Metrics are fake/inaccurate
- ❌ Could mislead users
- ❌ May still break some monitoring tools

### Option 3: cAdvisor Filesystem Support Extension

**Modification**: Add 9p filesystem support to cAdvisor

```go
// google/cadvisor/fs/fs.go

func isSupportedFilesystem(fsType string) bool {
    supportedFS := map[string]bool{
        "ext2": true,
        "ext3": true,
        "ext4": true,
        "xfs": true,
        "btrfs": true,
        "overlayfs": true,
        "9p": true,  // ADD THIS
    }
    return supportedFS[fsType]
}

func GetFsInfo(device string) (*FsInfo, error) {
    // ... existing code

    if fsType == "9p" {
        return get9pFsInfo(device)
    }

    // ... existing code
}

func get9pFsInfo(device string) (*FsInfo, error) {
    var statfs unix.Statfs_t
    err := unix.Statfs(device, &statfs)
    if err != nil {
        return nil, err
    }

    return &FsInfo{
        Device:     device,
        Type:       "9p",
        Capacity:   uint64(statfs.Blocks) * uint64(statfs.Bsize),
        Available:  uint64(statfs.Bavail) * uint64(statfs.Bsize),
        InodesFree: statfs.Ffree,
    }, nil
}
```

**Pros**:
- ✅ Proper fix at root cause
- ✅ Real metrics where possible
- ✅ Benefits entire community

**Cons**:
- ❌ Requires upstream cAdvisor changes
- ❌ Longer approval/merge cycle
- ❌ Maintenance burden on cAdvisor team

## Implementation Plan

### Phase 1: Proof of Concept (1-2 weeks)

**Goal**: Demonstrate kubelet can run without cAdvisor

**Tasks**:
1. Fork k3s repository
2. Implement stub cAdvisor (Option 2)
3. Test in gVisor sandbox
4. Document findings

**Success Criteria**:
- Kubelet starts successfully
- Node registers as Ready
- No cAdvisor-related errors

### Phase 2: Production-Ready Build (2-3 weeks)

**Goal**: Create maintainable custom build

**Tasks**:
1. Clean up implementation
2. Add configuration flags
3. Create build scripts
4. Test with real workloads
5. Performance benchmarking

**Success Criteria**:
- Stable for 24+ hours
- Pods can be scheduled and run
- Acceptable performance overhead

### Phase 3: Upstream Contribution (4-6 weeks)

**Goal**: Get changes merged upstream

**Tasks**:
1. Open issue on kubernetes/kubernetes
2. Propose design in KEP (Kubernetes Enhancement Proposal)
3. Implement with upstream requirements
4. Pass CI/CD tests
5. Address review feedback

**Success Criteria**:
- KEP approved
- PR merged
- Feature available in next release

## Build Instructions

### Prerequisites

```bash
# Install Go
wget https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

# Install build dependencies
apt-get install -y build-essential git
```

### Fork and Clone

```bash
# Fork k3s-io/k3s on GitHub
git clone https://github.com/YOUR_USERNAME/k3s.git
cd k3s

# Create feature branch
git checkout -b feature/optional-cadvisor
```

### Modify Source

**File**: `pkg/agent/containerd/containerd.go`

```go
// Add DisableCAdvisor flag
type Config struct {
    // ... existing fields
    DisableCAdvisor bool
}

// Modify cAdvisor initialization
func setupCAdvisor(cfg *Config) (cadvisor.Interface, error) {
    if cfg.DisableCAdvisor {
        log.Info("cAdvisor disabled, using stub implementation")
        return &stubCAdvisor{}, nil
    }

    // Existing cAdvisor initialization
    return cadvisor.New(...)
}
```

**File**: `pkg/agent/containerd/stub_cadvisor.go` (new file)

```go
package containerd

// Stub implementation from Option 2 above
type stubCAdvisor struct{}

func (s *stubCAdvisor) Start() error { return nil }
// ... implement required interface
```

### Build

```bash
# Build k3s
make

# Or build specific binary
go build -o k3s-custom ./cmd/server
```

### Test

```bash
# Run custom k3s
sudo ./k3s-custom server --disable-cadvisor=true

# Verify
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
```

## Configuration

### Kubelet Flags

```bash
# Disable cAdvisor (custom build)
--disable-cadvisor=true

# Reduce cAdvisor overhead (official build)
--housekeeping-interval=10m        # Default: 10s
--global-housekeeping-interval=5m  # Default: 1m
```

### k3s Server Flags

```bash
k3s server \
    --kubelet-arg="--disable-cadvisor=true" \
    --kubelet-arg="--housekeeping-interval=10m"
```

## Trade-offs

### What You Lose

**Metrics**:
- ❌ Container CPU usage
- ❌ Container memory usage
- ❌ Filesystem metrics
- ❌ Network I/O stats

**Features**:
- ❌ Horizontal Pod Autoscaler (requires metrics)
- ❌ Vertical Pod Autoscaler
- ❌ Resource quotas enforcement
- ❌ Detailed pod status

### What You Keep

**Core Functionality**:
- ✅ Pod scheduling
- ✅ Container lifecycle management
- ✅ Service networking
- ✅ Volume mounting
- ✅ ConfigMaps and Secrets
- ✅ RBAC

**Development Use Cases**:
- ✅ Helm chart testing
- ✅ Manifest validation
- ✅ API testing
- ✅ Controller development

## Alternatives Considered

### Alternative 1: External Metrics Server

**Idea**: Use Prometheus/custom metrics instead of cAdvisor

**Status**: ❌ Rejected
**Reason**: Still requires cAdvisor for kubelet to start

### Alternative 2: Patch at Runtime

**Idea**: Binary patch kubelet to skip cAdvisor checks

**Status**: ❌ Rejected
**Reason**: Fragile, breaks with updates, unmaintainable

### Alternative 3: Run kubelet in Host Namespace

**Idea**: Break out of sandbox for kubelet only

**Status**: ❌ Rejected
**Reason**: Security concerns, defeats sandbox purpose

### Alternative 4: Emulation (Current Research)

**Idea**: Use ptrace/FUSE to emulate cAdvisor requirements

**Status**: ⚠️ In Progress
**Reason**: Complex but may work; see Experiments 06-08

## Timeline

| Milestone | Duration | Status |
|-----------|----------|--------|
| Research & Design | 2 weeks | ✅ Complete |
| POC Implementation | 1 week | 🔧 In Progress |
| Testing & Validation | 1 week | ⏳ Pending |
| Documentation | 3 days | ⏳ Pending |
| Upstream Proposal | 2 weeks | ⏳ Pending |
| Community Review | 4-8 weeks | ⏳ Pending |

## Community Engagement

### Kubernetes SIG Node

**Forum**: kubernetes/community sig-node

**Proposal**:
- Open issue describing use case
- Reference gVisor compatibility
- Propose `--disable-cadvisor` flag
- Show POC results

### k3s Community

**Forum**: k3s-io/k3s discussions

**Value Proposition**:
- Enables k3s in more environments
- Reduces dependencies
- Optional feature (backwards compatible)

### cAdvisor Project

**Forum**: google/cadvisor issues

**Proposal**:
- Add 9p filesystem support
- Provide implementation
- Demonstrate use cases

## Success Metrics

**Technical**:
- [ ] Custom build successfully runs in gVisor
- [ ] Worker node stable for 24+ hours
- [ ] Pods can be scheduled and executed
- [ ] No cAdvisor errors in logs

**Community**:
- [ ] Positive feedback from SIG Node
- [ ] Issue/PR opened on kubernetes/kubernetes
- [ ] Discussion in k3s community
- [ ] At least 10 users testing POC

**Long-term**:
- [ ] Feature merged upstream
- [ ] Available in official release
- [ ] Documented in official docs
- [ ] Adopted by other sandbox projects

## Conclusion

A custom kubelet build without hard cAdvisor dependency is **technically feasible** and would **enable k3s in sandboxed environments** where current blockers exist.

**Recommended Approach**: Implement Option 2 (stub cAdvisor) as POC, then pursue Option 3 (upstream cAdvisor support) for long-term solution.

**Next Steps**:
1. Complete POC implementation
2. Validate in gVisor sandbox
3. Engage with upstream communities
4. Iterate based on feedback

---

**Document Status**: Draft
**Last Updated**: 2025-11-22
**Author**: Research Team
**Related**: Experiments 01-08, BREAKTHROUGH.md
