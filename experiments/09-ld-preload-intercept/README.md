# Experiment 09: LD_PRELOAD Interception

**Status:** Research - Limited applicability

## Hypothesis

Use LD_PRELOAD to intercept filesystem calls and redirect /proc/sys/* paths.

## Results

The interceptor works correctly for dynamically-linked programs, but **k3s is statically-linked Go**, so LD_PRELOAD has no effect on k3s itself.

## Files

- `ld_preload_interceptor.c` - C source for shared library
- `ld_preload_interceptor.so` - Compiled shared library
- `test_interceptor.c` - Test program
- `setup-fake-cgroups.sh` - Creates fake cgroup files
- `run-k3s-with-preload.sh` - Startup script (limited effect)

## Key Finding

While LD_PRELOAD works for dynamic binaries, it cannot intercept syscalls from statically-linked Go programs like k3s. This led to pursuing ptrace-based solutions in later experiments.

## See Also

- [Experiment 04](../04-ptrace-interception/) - Ptrace approach (works on static binaries)
- [Experiment 06](../06-enhanced-ptrace-statfs/) - Enhanced ptrace
