# Experiment 11: Tmpfs Cgroup Mount

**Status:** Research - Discovery

## Hypothesis

Mount cgroup files on tmpfs instead of the 9p filesystem to satisfy cAdvisor.

## Approach

Create tmpfs mounts for cgroup directories to provide a recognized filesystem type.

## Files

- `setup-tmpfs-cgroups.sh` - Script to set up tmpfs cgroup mounts

## Results

**Key Discovery:** Tmpfs is supported by cAdvisor and can be used for cgroup file storage. The previous approach was mounting 9p files incorrectly.

## Impact

This discovery led directly to Experiment 12 finding the `--local-storage-capacity-isolation=false` flag.

## See Also

- [Experiment 10](../10-bind-mount-cgroups/) - Bind mount approach
- [Experiment 12](../12-complete-solution/) - Complete solution with flag
