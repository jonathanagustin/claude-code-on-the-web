# Experiment 10: Bind Mount Cgroups

**Status:** Research - Partially successful

## Hypothesis

Use bind mounts to provide cgroup files that k3s/cAdvisor expects.

## Approach

Create fake cgroup files in tmpfs and bind mount them to expected locations.

## Files

- `setup-and-run.sh` - Main setup and run script
- `setup-cgroups-v2.sh` - Cgroups v2 specific setup

## Results

Bind mounts work in gVisor and can provide some cgroup files. However, cAdvisor still detects the 9p filesystem type on the root mount.

## Key Finding

Identified that the `--local-storage-capacity-isolation=false` flag could bypass cAdvisor filesystem checks (later confirmed in Experiment 12).

## See Also

- [Experiment 11](../11-tmpfs-cgroup-mount/) - Tmpfs discovery
- [Experiment 12](../12-complete-solution/) - Flag discovery
