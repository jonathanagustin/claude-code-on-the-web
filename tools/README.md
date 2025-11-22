# Claude Code Development Scripts

This directory contains scripts for setting up and managing the Claude Code development environment, particularly for Kubernetes development in sandboxed web sessions.

## Scripts

### setup-claude.sh

Automated installation script for Claude Code web environments that installs:
- Container runtime (Podman, Docker CLI, Buildah)
- Kubernetes tools (k3s, kubectl, containerd)
- Additional tools (helm, kubectx)

**Usage:**
```bash
bash scripts/setup-claude.sh
```

The script automatically detects if running in a Claude Code web session (`CLAUDE_CODE_REMOTE=true`) and only runs in that environment.

### start-k3s.sh

Attempts to start a local k3s cluster with worker node support using unshare for proper mount propagation.

**Usage:**
```bash
sudo bash scripts/start-k3s.sh
```

**Note:** This is experimental and may not work in all sandboxed environments. See `docs/k3s-sandboxed-environment.md` for details.

### start-k3s-docker.sh (Recommended)

Starts k3s in a Docker container with control-plane-only mode. This is the most reliable option for sandboxed environments.

**Usage:**
```bash
sudo bash scripts/start-k3s-docker.sh
```

**Features:**
- Fully working API server
- Perfect for Helm chart development
- Stable and reliable
- All kubectl operations work

**Limitations:**
- No worker node (control-plane only)
- Pods cannot actually run
- Cannot test runtime behavior

### start-k3s-dind.sh

Experimental Docker-in-Docker setup for k3s with worker nodes. Multiple modes available.

**Usage:**
```bash
sudo bash scripts/start-k3s-dind.sh [default|docker-runtime|privileged-all]
```

**Note:** This is experimental and may not work in all environments. See `docs/k3s-sandboxed-environment.md` for details.

## Known Limitations: k3s in Sandboxed Environments

The Claude Code web environment is a **sandboxed container environment** with significant restrictions that prevent k3s from running reliably with full worker node support:

### Technical Issues

1. **cAdvisor/cgroup Limitations**
   - Error: `Failed to start ContainerManager: failed to get rootfs info: unable to find data in memory cache`
   - The kubelet's cAdvisor cannot access cgroup filesystem data
   - This causes worker nodes to fail (control-plane works fine)

2. **Device Access**
   - Missing `/dev/kmsg` device (kernel message buffer)
   - Restricted access to system devices required by kubelet

3. **Overlay Filesystem**
   - `overlayfs` snapshotter fails with mount permission errors
   - `fuse-overlayfs` provides a workaround for some scenarios
   - `native` snapshotter partially works but has limitations

4. **Nested Container Restrictions**
   - Running containers within containers has limitations
   - Podman networking issues in the sandbox

### Why These Limitations Exist

Claude Code web sessions run in a **restricted sandbox** for security:
- No elevated kernel capabilities
- Limited cgroup access
- Restricted filesystem operations
- No access to raw devices

These restrictions are **by design** to ensure safety in multi-tenant environments.

## Alternative Approaches

### 1. Helm Testing Without Live Cluster (Recommended)

You can fully test and validate Helm charts without a running Kubernetes cluster:

```bash
# Lint the chart
helm lint <chart-path>/

# Validate template rendering
helm template test <chart-path>/ --debug

# Run unit tests
helm unittest <chart-path>/

# Test with different values
helm template test <chart-path>/ \
  --set key=value

# Generate full manifest
helm template test <chart-path>/ > /tmp/manifests.yaml
```

### 2. Use Control-Plane Only Mode

For Helm chart development, the control-plane-only mode (via `start-k3s-docker.sh`) provides everything needed:

```bash
# Start control-plane only cluster
sudo bash scripts/start-k3s-docker.sh

# Use kubectl for API operations
export KUBECONFIG=/root/.kube/config
kubectl get namespaces --insecure-skip-tls-verify
helm install myapp <chart-path>/
```

### 3. Deploy to External Cluster

If you have access to an external Kubernetes cluster:

```bash
# Configure kubectl to use external cluster
export KUBECONFIG=/path/to/your/kubeconfig

# Deploy using helm
helm install myapp <chart-path>/
```

### 4. Local Development (Outside Claude Code Web)

For local development on your own machine:

```bash
# Install k3d (Kubernetes in Docker)
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Create a cluster
k3d cluster create mycluster

# Use kubectl
kubectl get nodes
```

## Recommendations

**For Claude Code Web Sessions:**
1. Use `helm template` and `helm unittest` for chart development
2. Use `helm lint` for validation
3. Review rendered YAML manifests
4. Use `start-k3s-docker.sh` for control-plane-only testing
5. Test deployments on external clusters

**For Full Integration Testing:**
1. Use a local k3d/kind cluster on your development machine
2. Use a cloud-based Kubernetes cluster (EKS, GKE, AKS)
3. Use GitOps repositories for real deployments

## SessionStart Hook

The `.claude/hooks/SessionStart` hook automatically runs `setup-claude.sh` when a new Claude Code web session starts. This ensures all development tools are available.

## Troubleshooting

### CNI Plugin Issues
If you see "failed to find host-local" errors:
```bash
# Verify CNI plugins are copied (not symlinked)
ls -la /opt/cni/bin/host-local
# Should show actual file, not symlink
```

### Container Registry Issues
If Podman cannot pull images:
```bash
# Check registry configuration
cat /etc/containers/registries.conf | grep unqualified
```

### K3s Logs
If k3s fails to start:
```bash
# Check detailed logs
tail -f /var/log/k3s.log

# For Docker-based setup
docker logs k3s-server
```

### Common Errors

**"Failed to start ContainerManager: failed to get rootfs info"**
- This indicates the sandbox environment cannot support k3s worker nodes
- Use `start-k3s-docker.sh` for control-plane-only mode instead

**"bind-mount error"**
- Sandbox restrictions prevent certain mount operations
- Control-plane-only mode avoids these issues

## Contributing

When modifying these scripts:
1. Test in Claude Code web environment (`CLAUDE_CODE_REMOTE=true`)
2. Ensure idempotency (safe to run multiple times)
3. Add appropriate error handling and logging
4. Update this README with any new limitations or workarounds

## Additional Resources

- `docs/k3s-sandboxed-environment.md` - Detailed documentation on k3s in sandboxed environments
- `docs/k3s-gvisor/` - gVisor-specific k3s worker node solution (experimental)

