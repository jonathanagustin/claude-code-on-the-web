#!/bin/bash

echo "=========================================="
echo "Experiment 31: Patched Containerd"
echo "=========================================="
echo ""
echo "Goal: Patch containerd to skip kernel version check"
echo ""

WORK_DIR="/tmp/exp31"
rm -rf $WORK_DIR
mkdir -p $WORK_DIR

cd $WORK_DIR

# Step 1: Download containerd source (matching k3s version 2.1.4)
echo "Step 1: Downloading containerd v2.1.4 source..."
if [ ! -d "containerd" ]; then
    git clone --depth 1 --branch v2.1.4 https://github.com/containerd/containerd.git
fi
cd containerd

echo "✓ Source downloaded"
echo ""

# Step 2: Find and patch the kernel version check
echo "Step 2: Locating kernel version check..."

# The error mentions unprivileged_icmp and unprivileged_port
# Let's find where this check happens
grep -r "unprivileged_icmp" . | head -5

echo ""
echo "Step 3: Finding exact file with version check..."
FILE=$(grep -r "kernel version greater than" --include="*.go" . | head -1 | cut -d: -f1)

if [ -z "$FILE" ]; then
    echo "⚠️  Could not find kernel version check file"
    echo "Searching for unprivileged config..."
    grep -r "unprivileged_port" --include="*.go" . | head -10
    exit 1
fi

echo "Found: $FILE"
echo ""

# Step 4: Check file content
echo "Step 4: Examining file content..."
head -20 "$FILE"
echo ""

# Step 5: Apply fix directly
echo "Step 5: Patching kernel version check..."

# Backup original
cp "$FILE" "${FILE}.backup"

# The file is config_kernel_linux.go which contains supportsUnprivilegedFeatures()
# We need to make this function always return nil (success)

# Find the function and make it return nil
sed -i 's/return fmt\.Errorf.*kernel version greater than or equal to 4\.11.*$/return nil \/\/ gVisor compatibility: skip version check/' "$FILE"

if [ $? -eq 0 ]; then
    echo "✓ Patch applied!"
    echo ""
    echo "Verification - function after patch:"
    grep -A 10 "supportsUnprivilegedFeatures" "$FILE"
else
    echo "❌ Patch failed"
    exit 1
fi

echo ""

# Step 6: Build containerd
echo "Step 6: Building patched containerd..."
echo "This will take 3-5 minutes..."

# Install build dependencies if needed
if ! command -v go &> /dev/null; then
    echo "Go not found, using system Go"
fi

# Build
make clean
if make bin/containerd; then
    echo "✓ Build successful!"
    ls -lh bin/containerd
else
    echo "❌ Build failed"
    exit 1
fi

echo ""

# Step 7: Install patched binary
echo "Step 7: Installing patched containerd..."

sudo cp bin/containerd /usr/bin/containerd-gvisor-patched
sudo chmod +x /usr/bin/containerd-gvisor-patched

echo "✓ Installed to /usr/bin/containerd-gvisor-patched"
echo ""

# Step 8: Verify
echo "Step 8: Verifying installation..."
/usr/bin/containerd-gvisor-patched --version

echo ""
echo "=========================================="
echo "✅ Patched containerd ready!"
echo "=========================================="
echo ""
echo "Next: Use this binary with k3s"
echo "Binary: /usr/bin/containerd-gvisor-patched"
