#!/bin/bash

# Docker Capabilities Test Suite for gVisor/9p Environment
# Tests all Docker features and generates a capability matrix

set -e

LOGFILE="/tmp/docker-capabilities-test.log"
RESULTS="/tmp/docker-test-results.txt"

echo "================================================" | tee $LOGFILE
echo "Docker Capabilities Test Suite" | tee -a $LOGFILE
echo "Environment: gVisor with 9p filesystem" | tee -a $LOGFILE
echo "================================================" | tee -a $LOGFILE
echo "" | tee -a $LOGFILE

# Color output helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1" | tee -a $LOGFILE
    echo "PASS: $1" >> $RESULTS
}

fail() {
    echo -e "${RED}❌ FAIL${NC}: $1" | tee -a $LOGFILE
    echo "FAIL: $1" >> $RESULTS
}

warn() {
    echo -e "${YELLOW}⚠️  WARN${NC}: $1" | tee -a $LOGFILE
    echo "WARN: $1" >> $RESULTS
}

test_header() {
    echo "" | tee -a $LOGFILE
    echo "======================================" | tee -a $LOGFILE
    echo "TEST: $1" | tee -a $LOGFILE
    echo "======================================" | tee -a $LOGFILE
}

# Initialize results file
echo "Docker Capabilities Test Results" > $RESULTS
echo "Date: $(date)" >> $RESULTS
echo "" >> $RESULTS

# =============================================================================
# TEST 1: Docker Daemon
# =============================================================================
test_header "Docker Daemon Status"

if pgrep -x dockerd > /dev/null; then
    pass "Docker daemon is running"
else
    fail "Docker daemon is not running"
    echo "Starting dockerd..." | tee -a $LOGFILE
    dockerd --iptables=false > /var/log/dockerd.log 2>&1 &
    sleep 5
    if pgrep -x dockerd > /dev/null; then
        pass "Docker daemon started successfully"
    else
        fail "Failed to start Docker daemon"
        exit 1
    fi
fi

# Check Docker version
DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
echo "Docker version: $DOCKER_VERSION" | tee -a $LOGFILE

# Check storage driver
STORAGE_DRIVER=$(docker info --format '{{.Driver}}' 2>/dev/null || echo "unknown")
if [ "$STORAGE_DRIVER" = "vfs" ]; then
    pass "Storage driver: vfs (expected for 9p filesystem)"
elif [ "$STORAGE_DRIVER" = "overlay2" ]; then
    warn "Storage driver: overlay2 (unexpected on 9p)"
else
    fail "Storage driver: $STORAGE_DRIVER (unexpected)"
fi

# =============================================================================
# TEST 2: Image Operations
# =============================================================================
test_header "Image Operations"

# Test image list
if docker images > /dev/null 2>&1; then
    pass "docker images command works"
else
    fail "docker images command failed"
fi

# Test if we have a base image
if docker images | grep -q "rancher/k3s"; then
    pass "Base image available (rancher/k3s)"
    BASE_IMAGE="rancher/k3s:v1.33.5-k3s1"
else
    echo "No base image found, attempting to use cached image..." | tee -a $LOGFILE
    BASE_IMAGE="rancher/k3s:v1.33.5-k3s1"
fi

# =============================================================================
# TEST 3: Container Execution with Different Network Modes
# =============================================================================
test_header "Container Execution - Network Modes"

# Test host networking
if docker run --rm --network host --entrypoint /bin/sh $BASE_IMAGE -c "echo test" > /dev/null 2>&1; then
    pass "Container execution with --network host"
else
    fail "Container execution with --network host"
fi

# Test none networking
if docker run --rm --network none --entrypoint /bin/sh $BASE_IMAGE -c "echo test" > /dev/null 2>&1; then
    pass "Container execution with --network none"
else
    fail "Container execution with --network none"
fi

# Test bridge networking (expected to fail)
if docker run --rm --network bridge --entrypoint /bin/sh $BASE_IMAGE -c "echo test" > /dev/null 2>&1; then
    warn "Container execution with --network bridge (unexpected success)"
else
    fail "Container execution with --network bridge (expected - permission denied)"
fi

# =============================================================================
# TEST 4: Docker Build
# =============================================================================
test_header "Docker Build Capabilities"

# Create test Dockerfile
mkdir -p /tmp/docker-test-build
cat > /tmp/docker-test-build/Dockerfile << 'EOF'
FROM rancher/k3s:v1.33.5-k3s1
RUN echo "Test build at $(date)" > /test-build.txt
CMD ["/bin/sh", "-c", "cat /test-build.txt"]
EOF

# Test legacy builder
if docker build --network host -t docker-test-legacy /tmp/docker-test-build/ > /dev/null 2>&1; then
    pass "Docker build (legacy builder) with --network host"
else
    fail "Docker build (legacy builder) with --network host"
fi

# Test buildx
if command -v docker &> /dev/null && docker buildx version > /dev/null 2>&1; then
    if docker buildx build --network host -t docker-test-buildx /tmp/docker-test-build/ > /dev/null 2>&1; then
        pass "Docker buildx build"
    else
        fail "Docker buildx build"
    fi
else
    warn "Docker buildx not installed (skipping test)"
fi

# =============================================================================
# TEST 5: Volume Operations
# =============================================================================
test_header "Volume Operations"

# Test docker volume create
if docker volume create test-vol > /dev/null 2>&1; then
    pass "Docker volume create"

    # Test using the volume
    if docker run --rm --network host -v test-vol:/data --entrypoint /bin/sh \
       $BASE_IMAGE -c "echo test > /data/test.txt && cat /data/test.txt" > /dev/null 2>&1; then
        pass "Docker volume mount and use"
    else
        fail "Docker volume mount and use"
    fi

    # Cleanup
    docker volume rm test-vol > /dev/null 2>&1
else
    fail "Docker volume create"
fi

# Test host path mount
echo "test data" > /tmp/test-mount.txt
if docker run --rm --network host -v /tmp:/host-tmp:ro --entrypoint /bin/sh \
   $BASE_IMAGE -c "cat /host-tmp/test-mount.txt" > /dev/null 2>&1; then
    pass "Host path mount (bind mount)"
else
    fail "Host path mount (bind mount)"
fi
rm -f /tmp/test-mount.txt

# =============================================================================
# TEST 6: Container Management
# =============================================================================
test_header "Container Management"

# Start a background container
if docker run -d --name test-bg --network host --entrypoint /bin/sh \
   $BASE_IMAGE -c "sleep 30" > /dev/null 2>&1; then
    pass "Start background container"

    # Test docker exec
    if docker exec test-bg ps aux > /dev/null 2>&1; then
        pass "docker exec into running container"
    else
        fail "docker exec into running container"
    fi

    # Test docker stop
    if docker stop test-bg > /dev/null 2>&1; then
        pass "docker stop container"
    else
        fail "docker stop container"
    fi

    # Cleanup
    docker rm test-bg > /dev/null 2>&1
else
    fail "Start background container"
fi

# =============================================================================
# TEST 7: Network Operations
# =============================================================================
test_header "Network Operations"

# Test network list
if docker network ls > /dev/null 2>&1; then
    pass "docker network ls"
else
    fail "docker network ls"
fi

# Test network create
if docker network create test-network > /dev/null 2>&1; then
    pass "docker network create"

    # Test using the network (expected to fail)
    if docker run -d --name test-net-container --network test-network \
       --entrypoint /bin/sh $BASE_IMAGE -c "sleep 10" > /dev/null 2>&1; then
        warn "Container attach to custom network (unexpected success)"
        docker rm -f test-net-container > /dev/null 2>&1
    else
        fail "Container attach to custom network (expected - permission denied)"
    fi

    # Cleanup
    docker network rm test-network > /dev/null 2>&1
else
    fail "docker network create"
fi

# =============================================================================
# TEST 8: Image Build Features
# =============================================================================
test_header "Advanced Build Features"

# Test multi-stage build
cat > /tmp/docker-test-build/Dockerfile.multistage << 'EOF'
FROM rancher/k3s:v1.33.5-k3s1 AS builder
RUN echo "Build stage" > /build.txt

FROM rancher/k3s:v1.33.5-k3s1
COPY --from=builder /build.txt /final.txt
CMD ["/bin/sh", "-c", "cat /final.txt"]
EOF

if docker build --network host -f /tmp/docker-test-build/Dockerfile.multistage \
   -t docker-test-multistage /tmp/docker-test-build/ > /dev/null 2>&1; then
    pass "Multi-stage Docker build"
else
    fail "Multi-stage Docker build"
fi

# =============================================================================
# Cleanup
# =============================================================================
test_header "Cleanup"

# Remove test images
docker rmi -f docker-test-legacy docker-test-buildx docker-test-multistage > /dev/null 2>&1
rm -rf /tmp/docker-test-build

echo "" | tee -a $LOGFILE
echo "================================================" | tee -a $LOGFILE
echo "Test Results Summary" | tee -a $LOGFILE
echo "================================================" | tee -a $LOGFILE

# Count results
PASS_COUNT=$(grep -c "^PASS:" $RESULTS || echo "0")
FAIL_COUNT=$(grep -c "^FAIL:" $RESULTS || echo "0")
WARN_COUNT=$(grep -c "^WARN:" $RESULTS || echo "0")
TOTAL_COUNT=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT))

echo "" | tee -a $LOGFILE
echo "Total Tests: $TOTAL_COUNT" | tee -a $LOGFILE
echo -e "${GREEN}Passed: $PASS_COUNT${NC}" | tee -a $LOGFILE
echo -e "${RED}Failed: $FAIL_COUNT${NC}" | tee -a $LOGFILE
echo -e "${YELLOW}Warnings: $WARN_COUNT${NC}" | tee -a $LOGFILE

if [ $TOTAL_COUNT -gt 0 ]; then
    SUCCESS_RATE=$((100 * PASS_COUNT / TOTAL_COUNT))
    echo "" | tee -a $LOGFILE
    echo "Success Rate: ${SUCCESS_RATE}%" | tee -a $LOGFILE
fi

echo "" | tee -a $LOGFILE
echo "Detailed log: $LOGFILE" | tee -a $LOGFILE
echo "Results file: $RESULTS" | tee -a $LOGFILE
echo "" | tee -a $LOGFILE

# Expected failures summary
echo "Expected Failures (gVisor Limitations):" | tee -a $LOGFILE
echo "  - Bridge networking (permission denied)" | tee -a $LOGFILE
echo "  - Custom network attachment (permission denied)" | tee -a $LOGFILE
echo "" | tee -a $LOGFILE

echo "Test suite complete!" | tee -a $LOGFILE
