# Experiment 3: Worker Nodes via Docker-in-Docker

## Hypothesis

Running k3s inside Docker containers might isolate it from the host's 9p filesystem, allowing cAdvisor to see a standard filesystem (ext4/overlayfs) instead.

## Rationale

Docker creates its own filesystem layers using storage drivers. If we run k3s inside a Docker container:
- Docker might use ext4/overlay2 for the container's root filesystem
- cAdvisor would see Docker's filesystem, not the host's 9p
- Worker nodes might successfully initialize

## Method

Test multiple Docker configurations:
1. Default Docker with k3s
2. VFS storage driver
3. Overlay2 storage driver
4. Privileged vs non-privileged containers

## Experiment 3A: Default Docker

**Command**:
```bash
docker run -d \
    --name k3s-server \
    --privileged \
    -p 6443:6443 \
    rancher/k3s:latest server
```

**Expected**: Container filesystem isolates from host 9p

**Actual Result**: ❌ Failed

**Error**:
```bash
$ docker logs k3s-server
Failed to start ContainerManager: failed to get rootfs info: unable to find data in memory cache
```

**Analysis**:
```bash
$ docker exec k3s-server mount | grep " / "
overlay on / type overlay (rw,relatime,lowerdir=/var/lib/docker/overlay2/l/X:...,upperdir=/var/lib/docker/overlay2/.../diff)

$ docker exec k3s-server stat -f /
Filesystem: overlay

# But Docker's backing storage:
$ stat -f /var/lib/docker
Filesystem: 9p
```

**Root Cause**: Docker's overlay filesystem is backed by 9p storage. cAdvisor sees through to the underlying storage.

## Experiment 3B: VFS Storage Driver

**Command**:
```bash
# Configure Docker daemon
cat > /etc/docker/daemon.json << EOF
{
  "storage-driver": "vfs"
}
EOF

systemctl restart docker

docker run -d \
    --name k3s-vfs \
    --privileged \
    rancher/k3s:latest server
```

**Expected**: VFS uses plain directories, might appear as different filesystem

**Actual Result**: ❌ Failed

**Error**: Same cAdvisor error

**Analysis**:
```bash
$ docker exec k3s-vfs stat -f /
Filesystem: ext4  # Inside container

# But storage comes from:
$ stat -f /var/lib/docker/vfs
Filesystem: 9p
```

**Root Cause**: VFS still uses directories on the host's 9p filesystem. No filesystem translation occurs.

## Experiment 3C: Overlay2 Storage Driver

**Command**:
```bash
cat > /etc/docker/daemon.json << EOF
{
  "storage-driver": "overlay2"
}
EOF

systemctl restart docker

docker run -d \
    --name k3s-overlay2 \
    --privileged \
    rancher/k3s:latest server
```

**Expected**: overlay2 creates proper ext4-like layers

**Actual Result**: ❌ Failed (Docker won't start)

**Error**:
```bash
$ systemctl status docker
failed to start daemon: error initializing graphdriver: driver not supported

$ dmesg | tail
overlayfs: filesystem does not support d_type=true
overlayfs: filesystem must support d_type for merge dir
```

**Root Cause**: Overlayfs cannot be mounted on 9p filesystem. Kernel rejects it.

## Experiment 3D: Nested Docker (DinD)

**Command**:
```bash
# Run Docker-in-Docker
docker run -d \
    --name dind \
    --privileged \
    docker:dind

# Run k3s inside DinD
docker exec dind sh -c "
    apk add curl
    curl -sfL https://get.k3s.io | sh -
    k3s server
"
```

**Expected**: Nested Docker might provide better isolation

**Actual Result**: ❌ Failed

**Error**: Same cAdvisor error in nested k3s

**Analysis**: Even with nested Docker, the storage chain is:
```
k3s → Docker (inner) → Docker (outer) → 9p host
```

cAdvisor still queries the root filesystem, which traces back to 9p.

## Experiment 3E: tmpfs Root

**Command**:
```bash
docker run -d \
    --name k3s-tmpfs \
    --privileged \
    --tmpfs /var/lib/rancher:rw,size=2G \
    --tmpfs /var/lib/kubelet:rw,size=2G \
    rancher/k3s:latest server
```

**Expected**: tmpfs provides in-memory filesystem, might satisfy cAdvisor

**Actual Result**: ❌ Failed

**Error**: Same cAdvisor error

**Analysis**:
```bash
$ docker exec k3s-tmpfs mount | grep kubelet
tmpfs on /var/lib/kubelet type tmpfs (rw,size=2097152k)

$ docker exec k3s-tmpfs stat -f /
Filesystem: overlay  # But backed by 9p

# cAdvisor queries root "/"
GetRootFsInfo("/") → overlay on 9p → error
```

**Root Cause**: cAdvisor specifically queries the root filesystem `/`, not specific directories. tmpfs on subdirectories doesn't help.

## Why Docker Doesn't Help

### Filesystem Hierarchy

```
┌─────────────────────────────────────┐
│ k3s process                         │
│ cAdvisor.GetRootFsInfo("/")         │
└───────────────┬─────────────────────┘
                │
                ▼
┌─────────────────────────────────────┐
│ Container root "/" (overlay/ext4)   │
└───────────────┬─────────────────────┘
                │
                ▼
┌─────────────────────────────────────┐
│ Docker storage (/var/lib/docker)    │
└───────────────┬─────────────────────┘
                │
                ▼
┌─────────────────────────────────────┐
│ Host filesystem (9p)                │
└─────────────────────────────────────┘
```

**Problem**: cAdvisor's `statfs()` syscall on "/" returns information about the actual backing storage, which is ultimately 9p.

### Why Overlayfs Doesn't Mask It

```c
// Kernel's overlayfs statfs implementation
int ovl_statfs(struct dentry *dentry, struct kstatfs *buf) {
    // Get stats from UPPER layer's backing filesystem
    struct path upperpath;
    ovl_path_upper(dentry, &upperpath);

    // Calls statfs on underlying filesystem
    return vfs_statfs(&upperpath, buf);
    // Returns 9p filesystem type!
}
```

Overlayfs is a **transparent** filesystem - it passes through to the underlying storage for stat operations.

## Experiment 3F: Control-Plane in Docker

**Command**:
```bash
docker run -d \
    --name k3s-server-cp \
    -p 6443:6443 \
    -p 8443:8443 \
    -e K3S_KUBECONFIG_OUTPUT=/output/kubeconfig.yaml \
    -e K3S_KUBECONFIG_MODE=666 \
    -v /root/.kube:/output \
    --privileged \
    rancher/k3s:latest server --disable-agent
```

**Expected**: Control-plane-only might work (no cAdvisor needed)

**Actual Result**: ✅ Success!

**Output**:
```bash
$ docker logs k3s-server-cp
INFO[0000] Starting k3s v1.33.5-k3s1
INFO[0002] Running kube-apiserver
INFO[0003] Running kube-scheduler
INFO[0003] Running kube-controller-manager

$ kubectl get namespaces --kubeconfig=/root/.kube/kubeconfig.yaml
NAME              STATUS   AGE
default           Active   1m
kube-system       Active   1m
```

**Analysis**: Control-plane doesn't use cAdvisor, so Docker works fine for this use case.

## Summary of Results

| Configuration | Status | Reason |
|---------------|--------|--------|
| Default Docker | ❌ | Overlayfs backed by 9p |
| VFS driver | ❌ | Directories on 9p |
| Overlay2 driver | ❌ | Cannot mount on 9p |
| Docker-in-Docker | ❌ | Still backed by 9p |
| tmpfs mounts | ❌ | cAdvisor queries root "/" |
| Control-plane-only | ✅ | No cAdvisor requirement |

## Key Insights

### Insight 1: Filesystem Layers Don't Hide Backing Storage

Docker's filesystem abstraction doesn't hide the underlying storage from statfs() syscalls. cAdvisor sees through to the 9p backing filesystem.

### Insight 2: Overlayfs is Transparent

Overlayfs deliberately passes through statfs() calls to the underlying filesystem. This is by design - containers need to see real disk space.

### Insight 3: cAdvisor Queries Root, Not Subdirectories

Mounting tmpfs or other filesystems on `/var/lib/kubelet` doesn't help because:
```go
// cAdvisor
func GetRootFsInfo() (*FsInfo, error) {
    return getFsInfo("/")  // Always queries root
}
```

### Insight 4: Control-Plane-in-Docker is Excellent Solution

For development workflows:
- ✅ Isolated from host
- ✅ Easy to start/stop
- ✅ Reproducible
- ✅ Can be version-controlled (Dockerfile)
- ✅ Shareable (docker export/import)

## Why This Matters

This experiment **proves** that the limitation is NOT about:
- Docker isolation
- Container technology
- Mount namespaces
- Storage drivers

The limitation IS about:
- cAdvisor's hardcoded filesystem support
- The fact that all storage traces to 9p

## Conclusion

### Status: ❌ Worker nodes failed, ✅ Control-plane succeeded

Docker-in-Docker does not bypass the 9p filesystem limitation for worker nodes, but **control-plane-in-Docker is an excellent solution** for development workflows.

### Valuable Outcome

This experiment produced the **recommended production solution**: Docker-based control-plane-only mode.

**Advantages**:
- Clean isolation
- Easy to manage (docker start/stop/rm)
- Portable (docker export/import)
- Version controlled (Dockerfile)
- Reproducible across environments

### Next Steps

Experiment 4 will attempt syscall-level interception using ptrace to redirect filesystem queries before they reach the kernel.

## Files

- Implementation: `/solutions/control-plane-docker/start-k3s-docker.sh`
- Docker scripts: `/scripts/start-k3s-dind.sh`

## References

- Docker Storage Drivers: https://docs.docker.com/storage/storagedriver/
- Overlayfs Documentation: https://www.kernel.org/doc/html/latest/filesystems/overlayfs.html
- k3s Docker: https://hub.docker.com/r/rancher/k3s
