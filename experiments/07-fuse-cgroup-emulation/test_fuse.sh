#!/bin/bash
#
# Test script for FUSE cgroup emulator
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUSE_CGROUPFS="${SCRIPT_DIR}/fuse_cgroupfs"
MOUNT_POINT="/tmp/test-fuse-cgroup"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() {
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

info() {
    echo -e "${YELLOW}→${NC} $1"
}

# Cleanup
cleanup() {
    fusermount -u "$MOUNT_POINT" 2>/dev/null || true
    rmdir "$MOUNT_POINT" 2>/dev/null || true
}

trap cleanup EXIT

echo "FUSE cgroup Emulator Test Suite"
echo "================================"
echo ""

# Test 1: Build
info "Test 1: Building FUSE cgroupfs..."
if pkg-config --exists fuse; then
    gcc -Wall "${SCRIPT_DIR}/fuse_cgroupfs.c" -o "$FUSE_CGROUPFS" \
        `pkg-config fuse --cflags --libs` 2>&1 || fail "Compilation failed"
    pass "FUSE cgroupfs compiled"
else
    fail "libfuse-dev not installed"
fi

# Test 2: Mount
info "Test 2: Mounting FUSE filesystem..."
mkdir -p "$MOUNT_POINT"
"$FUSE_CGROUPFS" "$MOUNT_POINT" -o allow_other -f &
FUSE_PID=$!
sleep 1

if mountpoint -q "$MOUNT_POINT"; then
    pass "FUSE filesystem mounted"
else
    fail "Mount failed"
fi

# Test 3: Directory structure
info "Test 3: Checking directory structure..."
if [ -d "$MOUNT_POINT/cpu" ]; then
    pass "Subsystem directory exists"
else
    fail "Subsystem directory missing"
fi

# Test 4: Read static files
info "Test 4: Reading static cgroup files..."
CPU_SHARES=$(cat "$MOUNT_POINT/cpu/cpu.shares" 2>/dev/null)
if [ "$CPU_SHARES" = "1024" ]; then
    pass "Static file read correctly"
else
    fail "Static file content wrong: got '$CPU_SHARES', expected '1024'"
fi

# Test 5: Read dynamic files
info "Test 5: Reading dynamic cgroup files..."
USAGE=$(cat "$MOUNT_POINT/cpuacct/cpuacct.usage" 2>/dev/null)
if [ -n "$USAGE" ] && [ "$USAGE" -gt 0 ]; then
    pass "Dynamic file generated (usage: $USAGE ns)"
else
    fail "Dynamic file failed"
fi

# Test 6: File permissions
info "Test 6: Checking file permissions..."
PERMS=$(stat -c "%a" "$MOUNT_POINT/cpu/cpu.shares" 2>/dev/null)
if [ "$PERMS" = "644" ]; then
    pass "File permissions correct (644)"
else
    fail "File permissions wrong: $PERMS"
fi

# Test 7: Memory stats
info "Test 7: Reading memory statistics..."
MEM_USAGE=$(cat "$MOUNT_POINT/memory/memory.usage_in_bytes" 2>/dev/null)
if [ -n "$MEM_USAGE" ] && [ "$MEM_USAGE" -gt 0 ]; then
    pass "Memory usage reported: $(($MEM_USAGE / 1024 / 1024)) MB"
else
    fail "Memory usage failed"
fi

# Test 8: statfs
info "Test 8: Testing filesystem statistics..."
if stat -f "$MOUNT_POINT" > /dev/null 2>&1; then
    pass "statfs() works"
else
    fail "statfs() failed"
fi

# Test 9: Multiple reads consistency
info "Test 9: Testing read consistency..."
READ1=$(cat "$MOUNT_POINT/cpu/cpu.shares")
READ2=$(cat "$MOUNT_POINT/cpu/cpu.shares")
if [ "$READ1" = "$READ2" ]; then
    pass "Static files consistent across reads"
else
    fail "Inconsistent reads"
fi

# Test 10: List all subsystems
info "Test 10: Listing all subsystems..."
SUBSYS_COUNT=$(ls -1 "$MOUNT_POINT" | wc -l)
if [ "$SUBSYS_COUNT" -gt 5 ]; then
    pass "Found $SUBSYS_COUNT subsystems"
else
    fail "Too few subsystems: $SUBSYS_COUNT"
fi

echo ""
echo "================================"
echo -e "${GREEN}All tests passed!${NC}"
echo "================================"
echo ""
echo "FUSE cgroup emulator is working correctly"
echo ""
echo "Next steps:"
echo "  1. Integrate with ptrace interceptor (Experiment 06)"
echo "  2. Test with k3s kubelet"
echo "  3. Monitor cAdvisor compatibility"
echo ""
