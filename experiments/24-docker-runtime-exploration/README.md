# Experiment 24: Docker-in-Docker Runtime Exploration

## Context

After achieving 97% Kubernetes functionality in Experiment 22, we hit a final blocker:
- Pods reach ContainerCreating status
- CNI networking bypassed successfully (Experiment 23)
- runc init subprocess needs `/proc/sys/kernel/cap_last_cap`
- LD_PRELOAD doesn't propagate to namespaced subprocess

## Hypothesis

Exploring "Docker-in-Docker" (DinD) approaches to bypass subprocess isolation:
1. Run containers with a different runtime configuration
2. Use containerd runtime options to inject environment
3. Pre-create necessary files in container rootfs
4. Create custom runtime shim that handles /proc/sys access

## Environment Investigation

### Docker Daemon
```bash
$ docker info
Cannot connect to the Docker daemon at unix:///var/run/docker.sock
```
- Docker daemon doesn't work (no systemd in gVisor)

### Podman
```bash
$ podman info
Error: error marshaling into JSON: json: unsupported value: NaN
```
- Podman also fails in gVisor environment

## Alternative Approaches

Since traditional DinD isn't viable in gVisor, exploring:

### Approach 1: Custom Runtime Shim
Create a containerd-compatible runtime shim that:
- Wraps runc calls
- Provides /proc/sys files in container namespace
- Handles file redirection at runtime level

### Approach 2: Containerd Runtime Configuration
Use containerd's runtime options to:
- Set BinaryName to custom wrapper
- Pass environment variables via runtime config
- Inject LD_PRELOAD at containerd level

### Approach 3: Container Rootfs Preparation
Pre-create necessary files in the container rootfs:
- Mount /proc/sys files before runc init starts
- Use container hooks to populate files
- Modify container spec to include fake files

### Approach 4: crun Alternative Runtime
Test if crun (C-based runtime) has different subprocess behavior:
- Already configured in containerd config
- Might handle namespace isolation differently
- Could bypass runc-specific limitations

## Phase 1: Test crun Runtime

Since k3s already has crun configured, let's test if it behaves differently.

### Results

**crun Failure:**
```
OCI runtime create failed: unknown version specified
```
- crun fails with version specification error
- Different error than runc, but also doesn't work

**runc Progress - BREAKTHROUGH! 🎉**

Pods progressed from:
- **Old error** (7m36s-4m2s ago): `open /proc/sys/kernel/cap_last_cap: no such file or directory`
- **New error** (now): `unable to join session keyring: unable to create session key: disk quota exceeded`

The LD_PRELOAD wrapper successfully bypassed the cap_last_cap issue!

Evidence from pod events:
```
Warning  FailedCreatePodSandBox  7m36s  kubelet  ... cap_last_cap: no such file or directory
Warning  FailedCreatePodSandBox  7m16s  kubelet  ... cap_last_cap: no such file or directory
...
Warning  FailedCreatePodSandBox  10s    kubelet  ... unable to join session keyring
```

**LD_PRELOAD Wrapper Confirmation:**
- /usr/bin/runc and /usr/sbin/runc wrapped with C executable
- Sets LD_PRELOAD=/tmp/runc-preload.so
- Preload library redirects /proc/sys/* → /tmp/fake-procsys/*
- Successfully tested: `LD_PRELOAD=/tmp/runc-preload.so cat /proc/sys/kernel/cap_last_cap` returns "40"

## Phase 2: Session Keyring Investigation

### New Blocker: Linux Keyrings

Now failing at:
```
unable to join session keyring: unable to create session key: disk quota exceeded
```

This is a gVisor limitation - the environment doesn't support Linux keyrings properly.

**Discovery: runc --no-new-keyring Flag**

Found runc has a built-in option to bypass keyring creation:
```bash
$ /usr/bin/runc create --help | grep keyring
   --no-new-keyring    do not create a new session keyring for the container
```

Attempted to configure this via containerd runtime options:
1. Created /tmp/k3s-complete/agent/etc/containerd/config.toml.tmpl
2. Added NoNewKeyring = true to runc.options
3. Also added enable_unprivileged_ports = false and enable_unprivileged_icmp = false

Result: Configuration template was correctly applied to generated config.toml.

## Conclusions

### Major Achievements

1. **LD_PRELOAD Success** ✅
   - Successfully bypassed cap_last_cap file requirement
   - Pod errors progressed from "cap_last_cap: no such file or directory" to "session keyring" error
   - Confirms LD_PRELOAD wrapper technique works for /proc/sys redirection

2. **Session Keyring Discovery** ✅
   - Identified next blocker: Linux keyring support in gVisor
   - Found runc --no-new-keyring flag as potential solution
   - Containerd supports NoNewKeyring configuration option

3. **Alternative Runtime Testing** ✅
   - crun: Fails with "unknown version specified" error
   - Not a viable alternative to runc in this environment

### Current Status

Achieved progression through multiple blockers:
- **Layer 1**: cap_last_cap - SOLVED via LD_PRELOAD ✅
- **Layer 2**: Session keyring - IDENTIFIED, solution exists (--no-new-keyring)
- **Layer 3**: Unknown - not yet reached

### Files Created

- /tmp/runc-preload.c - LD_PRELOAD library for /proc/sys redirection
- /tmp/runc-preload.so - Compiled LD_PRELOAD library
- /tmp/runc-wrapper-v2.c - C wrapper that injects LD_PRELOAD
- /usr/bin/runc - Replaced with wrapper (original → runc.real)
- /usr/sbin/runc - Replaced with wrapper (original → runc.real)
- /tmp/k3s-complete/agent/etc/containerd/config.toml.tmpl - Runtime configuration
- /tmp/fake-procsys/kernel/cap_last_cap - Fake file (contains "40")

### Summary

Experiment 24 confirms that the LD_PRELOAD approach from previous sessions **successfully bypasses the cap_last_cap limitation**. Pods now progress to a new error: session keyring creation.

This represents real progress in overcoming gVisor's /proc/sys limitations. The runc --no-new-keyring flag offers a potential path forward for the next layer of blockers.
