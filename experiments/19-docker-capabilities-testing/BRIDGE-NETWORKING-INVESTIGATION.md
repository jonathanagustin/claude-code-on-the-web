# Bridge Networking Investigation

**Date**: 2025-11-23
**Question**: Can we enable bridge networking in gVisor by adjusting permissions or using alternatives?

## Background

Docker bridge networking fails with:
```
Error: failed to set up container networking:
  failed to add interface vethXXX to sandbox:
  failed to subscribe to link updates: permission denied
```

## Investigation

### Test 1: Check Available Capabilities

```bash
$ capsh --print | grep Current
Current: cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_kill,
         cap_setgid,cap_setuid,cap_setpcap,cap_net_bind_service,
         cap_net_admin,cap_net_raw,cap_sys_chroot,cap_sys_ptrace,
         cap_sys_admin,cap_mknod,cap_audit_write,cap_setfcap=eip
```

**Result**: ✅ We have `CAP_NET_ADMIN` (required for network operations)

### Test 2: Can We Create veth Pairs?

```bash
$ ip link add test-veth0 type veth peer name test-veth1
# Success - no error

$ ip link show | grep veth
9: test-veth0: <UP,LOWER_UP> mtu 1500
10: test-veth1: <UP,LOWER_UP> mtu 1500
```

**Result**: ✅ We CAN create veth pairs manually

### Test 3: What's Different About Docker?

**Manual veth creation**: Works
**Docker veth creation**: Fails

**Root Cause**: The error is NOT about creating the veth pair. The error is **"failed to subscribe to link updates"**.

Docker's network manager tries to subscribe to **netlink socket updates** to monitor network interface changes. This requires:
1. Creating a netlink socket (`socket(AF_NETLINK, ...)`)
2. Binding to RTMGRP_LINK group
3. Receiving real-time updates about interface changes

gVisor **restricts netlink socket operations** beyond basic interface creation.

### Test 4: Docker Error Analysis

From `/var/log/dockerd.log`:
```
level=error msg="Resolver Start failed for container c6cab47...,
  \"setting up DNAT/SNAT rules failed: (iptables failed: iptables --wait -t nat -N DOCKER_OUTPUT:
  iptables: Failed to initialize nft: Protocol not supported\\n (exit status 1))\""
```

Additional issues found:
- iptables/nftables not fully supported
- Netlink subscription blocked
- IPSEC/Conntrack modules unavailable

### Test 5: Alternative Docker Configurations

Attempted:
```bash
dockerd --iptables=false --userland-proxy=false --ip-masq=false --ipv6=false
```

**Result**: ❌ Docker daemon failed to start with this configuration

## Why Bridge Networking Cannot Work

### Fundamental Limitations

1. **Netlink Socket Restrictions**
   - gVisor restricts `NETLINK_ROUTE` socket operations
   - Can create interfaces but can't subscribe to updates
   - Docker's libnetwork requires real-time link monitoring

2. **iptables/nftables Unavailable**
   ```
   iptables: Failed to initialize nft: Protocol not supported
   ```
   - Required for NAT rules (port mapping)
   - Required for network isolation
   - Not available in gVisor sandbox

3. **Kernel Module Limitations**
   - No IPSEC modules
   - No Conntrack modules
   - Limited cgroup support

## Alternatives and Workarounds

### ✅ Option 1: Host Networking (Recommended)

**Works perfectly** - already documented in main README

```bash
docker run --network host myimage
```

**Advantages**:
- Full functionality
- No permission issues
- Simple and reliable

**Disadvantages**:
- No network isolation
- Port conflicts possible
- All containers share host network

### ❌ Option 2: Run Docker on the Host (Outside Sandbox)

**Not applicable** - We ARE in the sandbox, can't escape it

### ⚠️ Option 3: Alternative Container Runtimes

**Podman** (rootless containers):
- Same limitations in gVisor
- Also requires netlink for bridge mode
- Host networking works

**containerd** (via nerdctl):
- Not tested but likely same issues
- Low-level runtime has same kernel requirements

## Comparison with Other Sandboxes

This limitation is **specific to gVisor's security model**:

| Environment | veth Creation | Netlink Subscribe | Bridge Mode |
|-------------|---------------|-------------------|-------------|
| **gVisor** (our sandbox) | ✅ | ❌ | ❌ |
| **Docker Desktop** (uses VM) | ✅ | ✅ | ✅ |
| **Native Linux** | ✅ | ✅ | ✅ |
| **LXC/LXD** | ✅ | ✅ | ✅ |

gVisor intentionally restricts netlink operations for security isolation.

## Conclusion

### Can We Enable Bridge Networking?

**Answer: No**, not without modifying the gVisor sandbox itself.

**Why:**
1. ✅ We have sufficient capabilities (CAP_NET_ADMIN)
2. ✅ We can create veth pairs
3. ❌ **gVisor blocks netlink socket subscriptions** (security restriction)
4. ❌ iptables/nftables unavailable (required for bridge features)

This is **by design** - gVisor's security model intentionally restricts these operations.

### What Works Instead?

**Host Networking** provides full Docker functionality:

```bash
# Single containers
docker run --network host myapp

# Multi-container apps
# See: scripts/docker-compose-host-network.yml
version: '3.8'
services:
  db:
    network_mode: host
  app:
    network_mode: host
```

**Limitations of host networking**:
- Services must use different ports
- No container-to-container DNS
- No network isolation
- But: **Fully functional** and **production-ready**

### Is This a Blocker?

**No** - for most development use cases:

| Use Case | Status with Host Networking |
|----------|----------------------------|
| Build Docker images | ✅ Perfect |
| Run databases/services | ✅ Works (different ports) |
| k3s control-plane | ✅ Perfect (Helm development) |
| CI/CD pipelines | ✅ Works |
| Multi-container apps | ⚠️ Works (no isolation) |
| Network policy testing | ❌ Not possible |

**Recommendation**: Accept host networking as the standard mode for this environment.

## References

- gVisor netlink support: https://gvisor.dev/docs/user_guide/networking/
- Docker networking docs: https://docs.docker.com/network/
- libnetwork source: https://github.com/moby/libnetwork
- Experiment 19 README: Full Docker capabilities documentation

## Summary

**Question**: Can we control permissions or use alternatives?

**Answer**:
- ✅ Permissions are sufficient (we have CAP_NET_ADMIN)
- ❌ gVisor sandbox blocks netlink subscriptions (security by design)
- ✅ Alternative: Host networking works perfectly
- ✅ This is the **recommended approach** for Docker in sandboxed environments

The limitation is **intentional security**, not a bug or misconfiguration.
