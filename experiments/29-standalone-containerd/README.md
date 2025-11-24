# Experiment 29: Standalone Containerd

**Status:** Research

## Hypothesis

Run containerd standalone (without k3s) to isolate container runtime behavior in gVisor.

## Approach

Bypass k3s entirely and test containerd directly to understand which specific operations fail in the gVisor sandbox.

## Files

- `run-standalone.sh` - Script to start and test standalone containerd

## Results

Helped identify that the container execution blockers are in the containerd/runc layer, not k3s-specific.

## See Also

- [Experiment 31](../31-patched-containerd/) - Patched containerd
- [Experiment 32](../32-preload-images/) - Final solution
