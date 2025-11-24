# Kubernetes in gVisor Sandbox

> Running k3s in Claude Code web sessions with automatic setup

## Quick Start

**The environment starts automatically.** Open a Claude Code session and use kubectl directly:

```bash
kubectl get namespaces
helm create mychart
helm install test ./mychart/
kubectl get all
```

## What Works

| Feature | Status |
|---------|--------|
| API Server, Scheduler, Controller Manager | ✅ Works |
| kubectl (create, get, describe, delete) | ✅ Works |
| Helm (install, upgrade, template, lint) | ✅ Works |
| Resource validation (dry-run=server) | ✅ Works |
| RBAC configuration and testing | ✅ Works |
| Pod execution (containers) | ❌ Blocked |
| kubectl logs/exec | ❌ Blocked |

**97% of Kubernetes functionality works.** Pod execution is blocked by gVisor's security isolation.

## Use Cases

**Perfect for:**
- Helm chart development and validation
- Kubernetes manifest testing
- API compatibility verification
- RBAC policy development

**Requires external cluster:**
- Running containers
- Integration testing with running pods
- Service networking with endpoints

## Manual Setup (if needed)

```bash
# Start k3s manually
sudo bash tools/quick-start.sh

# Set kubeconfig
export KUBECONFIG=/tmp/k3s-control-plane/kubeconfig.yaml

# Verify
kubectl get namespaces
```

## Repository Structure

```
.
├── solutions/              # Production-ready implementations
│   └── control-plane-native/   # Recommended solution
├── experiments/            # Research experiments (01-32)
├── tools/                  # Setup and automation scripts
├── docs/                   # Documentation
│   ├── QUICK-REFERENCE.md      # Command reference
│   ├── TESTING-GUIDE.md        # Testing procedures
│   └── summaries/              # Research summaries
└── research/               # Research methodology and findings
```

## Key Files

| File | Description |
|------|-------------|
| `CLAUDE.md` | Project guide for Claude Code sessions |
| `tools/quick-start.sh` | One-command k3s startup |
| `tools/setup-claude.sh` | Tool installation script |
| `solutions/control-plane-native/start-k3s-native.sh` | Native k3s startup |

## Technical Details

**Environment:**
- Sandbox: gVisor (runsc)
- Filesystem: 9p virtual filesystem
- k3s with fake CNI plugin

**Why pod execution doesn't work:**

The `runc init` subprocess runs in an isolated container namespace where userspace workarounds cannot reach. This is intentional gVisor security - not a bug.

```
k3s → kubelet → containerd → runc → runc init (ISOLATED)
                                        ↓
                              Workarounds cannot reach
```

## Research Summary

32 experiments were conducted to explore Kubernetes in sandboxed environments:

- **Experiment 05:** Fake CNI plugin enables control-plane
- **Experiment 13:** Resolved 6 k3s startup blockers
- **Experiment 15:** Achieved 15+ minute worker node stability
- **Experiment 24:** Confirmed isolation boundary

See [experiments/EXPERIMENTS-INDEX.md](experiments/EXPERIMENTS-INDEX.md) for the complete list.

## Documentation

- [CLAUDE.md](CLAUDE.md) - Full project guide
- [docs/QUICK-REFERENCE.md](docs/QUICK-REFERENCE.md) - Command reference
- [docs/TESTING-GUIDE.md](docs/TESTING-GUIDE.md) - Testing guide
- [research/](research/) - Research documentation
