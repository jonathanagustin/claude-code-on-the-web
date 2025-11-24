# Solutions

Production-ready implementations for running k3s in gVisor sandboxed environments.

## Available Solutions

### control-plane-native/ (Recommended)

**Status:** ✅ Production-ready

Native k3s control-plane with fake CNI plugin. Provides full Kubernetes API access for kubectl and Helm operations.

```bash
sudo bash solutions/control-plane-native/start-k3s-native.sh
export KUBECONFIG=/tmp/k3s-control-plane/kubeconfig.yaml
kubectl get namespaces
```

**Use for:** Helm chart development, manifest validation, API testing

### control-plane-docker/

**Status:** ⚠️ Legacy (use control-plane-native instead)

Docker-based k3s control-plane. Still works but native solution is simpler and more reliable.

```bash
sudo bash solutions/control-plane-docker/start-k3s-docker.sh
export KUBECONFIG=/root/.kube/config
kubectl get namespaces --insecure-skip-tls-verify
```

### worker-ptrace-experimental/

**Status:** 🔬 Research/experimental

Ptrace-based syscall interception for worker node functionality. Proof-of-concept from Experiment 04.

**Use for:** Research into syscall interception techniques

### worker-stable-production/

**Status:** 🔬 Research

Enhanced ptrace interceptor for stable worker node operation. Based on Experiment 15 findings.

**Use for:** Research into worker node stability

### docker-bridge-networking/

**Status:** 🔬 Research

Bridge networking configuration for Docker containers in gVisor.

**Use for:** Research into container networking

## Quick Comparison

| Solution | Status | Pod Execution | Recommended Use |
|----------|--------|---------------|-----------------|
| control-plane-native | Production | No | Helm/kubectl development |
| control-plane-docker | Legacy | No | Fallback option |
| worker-ptrace-experimental | Research | Limited | Syscall research |
| worker-stable-production | Research | Limited | Worker node research |
| docker-bridge-networking | Research | N/A | Networking research |

## See Also

- [tools/quick-start.sh](../tools/quick-start.sh) - Automated startup script
- [experiments/](../experiments/) - Research experiments leading to these solutions
