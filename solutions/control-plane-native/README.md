# Native k3s Control-Plane

**Status:** ✅ Production-ready

Native k3s control-plane with fake CNI plugin. This is the recommended solution for running Kubernetes in Claude Code web sessions.

## Quick Start

```bash
sudo bash start-k3s-native.sh
export KUBECONFIG=/tmp/k3s-control-plane/kubeconfig.yaml
kubectl get namespaces
```

## What It Provides

- Full Kubernetes API access
- kubectl operations (create, get, describe, delete)
- Helm chart installation and testing
- Resource validation (dry-run=server)
- RBAC configuration

## How It Works

1. Creates fake CNI plugin at `/opt/cni/bin/host-local`
2. Starts k3s in control-plane-only mode
3. Disables agent components that require pod execution
4. Provides kubeconfig for kubectl access

## Files

- `start-k3s-native.sh` - Main startup script

## Data Locations

- Kubeconfig: `/tmp/k3s-control-plane/kubeconfig.yaml`
- Data: `/tmp/k3s-control-plane/`
- Logs: `/tmp/k3s-control-plane/logs/`

## See Also

- [Experiment 05](../../experiments/05-fake-cni-breakthrough/) - Original breakthrough
- [tools/quick-start.sh](../../tools/quick-start.sh) - Automated startup
