#!/bin/bash

echo "=== Experiment 25: Direct Container Execution Testing ==="
echo ""
echo "Testing if containers can run directly outside k3s context"
echo "This will determine if the blocker is k3s-specific or fundamental to gVisor"
echo ""

# Test 1: Podman (if available)
echo "=== Test 1: Podman ==="
if command -v podman &> /dev/null; then
    echo "Podman found, attempting to run container..."

    # Try to run a simple container
    podman run --rm alpine:latest echo "Podman container executed successfully" 2>&1 | tee /tmp/podman-test.log

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo "✓ Podman container execution: SUCCESS"
    else
        echo "✗ Podman container execution: FAILED"
        echo "Error details:"
        tail -20 /tmp/podman-test.log
    fi
else
    echo "⊘ Podman not available"
fi

echo ""

# Test 2: Docker (if available)
echo "=== Test 2: Docker ==="
if command -v docker &> /dev/null; then
    echo "Docker found, checking if daemon is running..."

    if docker ps &> /dev/null; then
        echo "Docker daemon is running, attempting to run container..."

        # Try to run a simple container
        docker run --rm alpine:latest echo "Docker container executed successfully" 2>&1 | tee /tmp/docker-test.log

        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            echo "✓ Docker container execution: SUCCESS"
        else
            echo "✗ Docker container execution: FAILED"
            echo "Error details:"
            tail -20 /tmp/docker-test.log
        fi
    else
        echo "⊘ Docker daemon not running, attempting to start..."

        # Try to start Docker daemon
        dockerd > /tmp/dockerd.log 2>&1 &
        DOCKERD_PID=$!

        echo "Waiting 10 seconds for Docker daemon to start..."
        sleep 10

        if docker ps &> /dev/null; then
            echo "Docker daemon started, attempting to run container..."

            docker run --rm alpine:latest echo "Docker container executed successfully" 2>&1 | tee /tmp/docker-test.log

            if [ ${PIPESTATUS[0]} -eq 0 ]; then
                echo "✓ Docker container execution: SUCCESS"
            else
                echo "✗ Docker container execution: FAILED"
                echo "Error details:"
                tail -20 /tmp/docker-test.log
            fi

            # Stop dockerd
            kill $DOCKERD_PID 2>/dev/null
        else
            echo "✗ Failed to start Docker daemon"
            echo "Docker daemon logs:"
            tail -30 /tmp/dockerd.log
        fi
    fi
else
    echo "⊘ Docker not available"
fi

echo ""

# Test 3: Direct runc (if available)
echo "=== Test 3: Direct runc ==="
if command -v runc &> /dev/null; then
    echo "runc found, attempting to create and run container..."

    # Create a minimal container bundle
    mkdir -p /tmp/runc-test/rootfs

    # Create a minimal rootfs
    if command -v podman &> /dev/null; then
        # Export alpine filesystem using podman
        podman pull alpine:latest 2>&1 | head -5
        CONTAINER_ID=$(podman create alpine:latest)
        podman export $CONTAINER_ID | tar -C /tmp/runc-test/rootfs -xf -
        podman rm $CONTAINER_ID
    else
        echo "⊘ Cannot create rootfs without podman or docker"
        echo "Skipping runc test"
        echo ""
        echo "=== Experiment 25 Complete ==="
        exit 0
    fi

    # Generate config.json
    cd /tmp/runc-test
    runc spec

    # Modify config to run a simple echo command
    cat config.json | sed 's/"sh"/"echo", "runc container executed successfully"/' > config.json.tmp
    mv config.json.tmp config.json

    # Try to run the container
    runc run test-container 2>&1 | tee /tmp/runc-test.log

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo "✓ runc container execution: SUCCESS"
    else
        echo "✗ runc container execution: FAILED"
        echo "Error details:"
        tail -20 /tmp/runc-test.log

        # Check for specific errors
        if grep -q "cap_last_cap" /tmp/runc-test.log; then
            echo ""
            echo "⚠️  Found cap_last_cap error - same blocker as k3s!"
        fi

        if grep -q "session keyring" /tmp/runc-test.log; then
            echo ""
            echo "⚠️  Found session keyring error - same blocker as k3s!"
        fi
    fi

    # Cleanup
    cd /home/user/claude-code-on-the-web
    rm -rf /tmp/runc-test
else
    echo "⊘ runc not available"
fi

echo ""
echo "=== Experiment 25 Complete ==="
echo ""
echo "Results Summary:"
echo "- Podman: $([ -f /tmp/podman-test.log ] && grep -q 'successfully' /tmp/podman-test.log && echo 'SUCCESS' || echo 'FAILED/NOT TESTED')"
echo "- Docker: $([ -f /tmp/docker-test.log ] && grep -q 'successfully' /tmp/docker-test.log && echo 'SUCCESS' || echo 'FAILED/NOT TESTED')"
echo "- runc: $([ -f /tmp/runc-test.log ] && grep -q 'successfully' /tmp/runc-test.log && echo 'SUCCESS' || echo 'FAILED/NOT TESTED')"
echo ""
echo "Conclusion:"
if grep -q 'successfully' /tmp/podman-test.log 2>/dev/null || grep -q 'successfully' /tmp/docker-test.log 2>/dev/null; then
    echo "✓ Container execution WORKS outside k3s - the blocker is k3s-specific!"
    echo "   Next step: Configure k3s to use working runtime"
elif grep -q 'cap_last_cap' /tmp/runc-test.log 2>/dev/null; then
    echo "✗ Container execution FAILS with same error - fundamental gVisor limitation"
    echo "   The blocker affects ALL runc-based runtimes"
else
    echo "⚠️  Tests inconclusive - manual review of logs needed"
fi
