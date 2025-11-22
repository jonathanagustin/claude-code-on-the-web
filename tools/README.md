# Tools Directory

Automation scripts for the Kubernetes in gVisor research environment.

## Available Scripts

### `setup-claude.sh` - Environment Setup

**Purpose**: Installs all required tools for Kubernetes development in sandboxed environments.

**Auto-runs**: Via `.claude/hooks/SessionStart` when `CLAUDE_CODE_REMOTE=true`

**What it installs**:
- Container runtime (Podman, Docker CLI, Buildah)
- Kubernetes core (k3s, kubectl, containerd)
- Development tools (Helm, kubectx, kubens)
- Research tools (inotify-tools, strace, lsof)

**Usage**:
```bash
bash tools/setup-claude.sh
```

### `quick-start.sh` - One-Command Cluster Start

**Purpose**: Starts the production-ready k3s control-plane and verifies it's working.

**What it does**:
1. Starts k3s control-plane using Experiment 05 solution
2. Waits for cluster to be ready
3. Displays cluster status
4. Shows quick-start examples

**Usage**:
```bash
sudo bash tools/quick-start.sh
```

**Output**:
- Cluster status (nodes, namespaces)
- Quick examples for Helm, kubectl, RBAC testing

## Installed Components

### Container Runtime
- **Podman**: Container management (Docker-compatible)
- **Buildah**: Container image building
- **Docker CLI**: Emulated via Podman

### Kubernetes Core
- **k3s**: Lightweight Kubernetes distribution
- **kubectl**: Kubernetes CLI
- **containerd**: Container runtime (embedded in k3s)

### Development Tools
- **Helm**: Kubernetes package manager
- **helm-unittest**: Chart testing plugin
- **kubectx/kubens**: Context switching utilities

### Research Tools
- **inotify-tools**: Real-time file system monitoring
- **strace**: System call tracing
- **lsof**: File and process inspection

## Environment Variables

Setup scripts configure:
- `KUBECONFIG=/etc/rancher/k3s/k3s.yaml`
- `PATH=/opt/cni/bin:$PATH`

## Related Documentation

- **PROGRESS-SUMMARY.md** - Complete research findings
- **experiments/** - Chronological experiments (01-17)
- **solutions/** - Production-ready implementations

## Quick Start Workflow

New session? Run this:
```bash
# Install all tools (auto-runs via SessionStart hook)
bash tools/setup-claude.sh

# Start the control-plane
sudo bash tools/quick-start.sh

# Verify it's working
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get namespaces --insecure-skip-tls-verify

# Create and deploy a Helm chart
helm create mychart
helm install test ./mychart/
kubectl get all --insecure-skip-tls-verify
```

## Important Notes

### What Works ✅
- Full Kubernetes control-plane
- kubectl operations (100% functional)
- Helm chart development and testing
- YAML validation and server-side dry runs
- RBAC policy testing

### What Doesn't Work ❌
- Pod execution (blocked by cgroup requirements)
- Container logs/exec (no running containers)
- Service networking with endpoints

See **PROGRESS-SUMMARY.md** for complete analysis of limitations and workarounds.
