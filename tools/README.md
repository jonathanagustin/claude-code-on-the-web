# Tools

Automation scripts for Kubernetes development in Claude Code web sessions.

## Scripts

### quick-start.sh

**Purpose:** One-command k3s startup

```bash
sudo bash tools/quick-start.sh
```

Starts the production-ready k3s control-plane and verifies it's working.

### setup-claude.sh

**Purpose:** Install all development tools

```bash
bash tools/setup-claude.sh
```

**Auto-runs** via `.claude/hooks/SessionStart` when `CLAUDE_CODE_REMOTE=true`

**Installs:**
- Container runtime (Podman, Docker CLI, Buildah)
- Kubernetes tools (k3s, kubectl, containerd)
- Development tools (Helm, kubectx, kubens)
- Research tools (inotify-tools, strace, lsof)

### start-k3s.sh

**Purpose:** Legacy k3s startup (use quick-start.sh instead)

## Environment Variables

Scripts configure:
- `KUBECONFIG=/tmp/k3s-control-plane/kubeconfig.yaml`
- `PATH=/opt/cni/bin:$PATH`

## Quick Start

```bash
# Environment auto-starts, just use kubectl:
kubectl get namespaces

# Or manually:
sudo bash tools/quick-start.sh
kubectl get namespaces
```

## See Also

- [solutions/](../solutions/) - Production solutions
- [experiments/](../experiments/) - Research experiments
- [CLAUDE.md](../CLAUDE.md) - Project guide
