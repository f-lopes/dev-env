#!/usr/bin/env bash
#
# test-mise-tart.sh — Test the mise development environment in an ephemeral macOS VM
#
# Usage:
#   ./scripts/test-mise-tart.sh [tahoe|golden-gate]
#
# Examples:
#   ./scripts/test-mise-tart.sh              # Defaults to macOS 26 (Tahoe)
#   ./scripts/test-mise-tart.sh golden-gate  # macOS 27 (Golden Gate)
#   ./scripts/test-mise-tart.sh tahoe        # macOS 26 (Tahoe)
#
# Requirements:
#   - tart CLI installed (https://tart.run)
#   - sshpass installed (`brew install sshpass`)
#
# What it does:
#   1. Clones and runs an ephemeral macOS VM
#   2. Waits for SSH to become available (uses default admin/admin credentials)
#   3. Installs mise inside the VM
#   4. Runs `mise install` to provision all tools from .mise.toml
#   5. Reports the installed tools and their versions
#   6. Cleans up the VM after testing
#

set -euo pipefail

# --- Configuration ---
VM_NAME="mise-test-$(date +%Y%m%d-%H%M%S)"
MEMORY_MB=16384  # 16 GB in megabytes
TIMEOUT=600  # Max seconds to wait for SSH
SSH_USER="admin"
SSH_PASS="admin"  # Default password for Cirrus Labs base images

# macOS version selection
MACOS_VERSION="${1:-tahoe}"
case "$MACOS_VERSION" in
    tahoe|macos26|26)
        IMAGE="ghcr.io/cirruslabs/macos-tahoe-base"
        echo "→ Using macOS 26 (Tahoe) base image"
        ;;
    golden-gate|macos27|27|gg)
        IMAGE="ghcr.io/cirruslabs/macos-golden-gate-base"
        echo "→ Using macOS 27 (Golden Gate) base image"
        ;;
    *)
        echo "❌ Unknown macOS version: $MACOS_VERSION"
        echo "   Supported: tahoe, golden-gate"
        exit 1
        ;;
esac

# Check for sshpass
if ! command -v sshpass >/dev/null 2>&1; then
    echo "❌ sshpass is not installed. Install it with: brew install sshpass"
    exit 1
fi

# Repo URL (default to current directory's git remote, or prompt)
REPO_URL="${MISE_TEST_REPO:-$(cd "$(dirname "$0")/.." && git remote get-url origin 2>/dev/null || echo '')}"
if [ -z "$REPO_URL" ]; then
    echo "⚠️  No git remote found. Set MISE_TEST_REPO env var to specify the repository URL."
    echo "   The VM will skip cloning and only test mise installation."
fi

# --- Helper Functions ---
cleanup() {
    echo ""
    echo "=== Cleanup ==="
    echo "→ Stopping VM: $VM_NAME"
    tart stop "$VM_NAME" 2>/dev/null || true
    echo "→ Deleting VM: $VM_NAME"
    tart delete "$VM_NAME" 2>/dev/null || true
    echo "✓ VM cleaned up"
}

# Set trap to clean up on exit
trap cleanup EXIT

# SSH helper function
ssh_to_vm() {
    local ip
    ip=$(tart ip "$VM_NAME")
    sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        "${SSH_USER}@${ip}" "$@"
}

# --- Step 1: Start the VM ---
echo ""
echo "=== Step 1: Starting ephemeral VM ==="
echo "→ Image: $IMAGE"
echo "→ VM name: $VM_NAME"
echo "→ Memory: $((MEMORY_MB / 1024))GB"

tart clone "$IMAGE" "$VM_NAME"
tart set "$VM_NAME" --memory "$MEMORY_MB"
tart run "$VM_NAME" --no-graphics &

TART_PID=$!
echo "→ tart run started (PID: $TART_PID)"

# --- Step 2: Wait for SSH ---
echo ""
echo "=== Step 2: Waiting for SSH (timeout: ${TIMEOUT}s) ==="
elapsed=0
while [ $elapsed -lt $TIMEOUT ]; do
    if ssh_to_vm 'echo ready' >/dev/null 2>&1; then
        echo "✓ SSH is ready after ${elapsed}s"
        break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    if [ $((elapsed % 30)) -eq 0 ]; then
        echo "  ... waiting (${elapsed}s / ${TIMEOUT}s)"
    fi
done

if [ $elapsed -ge $TIMEOUT ]; then
    echo "❌ SSH timeout after ${TIMEOUT}s. VM may not have started correctly."
    exit 1
fi

# --- Step 3: Install mise in the VM ---
echo ""
echo "=== Step 3: Installing mise in the VM ==="

ssh_to_vm << 'REMOTE_SCRIPT'
set -euo pipefail

echo "→ Installing mise..."
curl https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"

# Verify mise installation
if mise --version; then
    echo "✓ mise installed successfully"
else
    echo "❌ mise installation failed"
    exit 1
fi
REMOTE_SCRIPT

# --- Step 4: Clone repo and run mise install ---
echo ""
echo "=== Step 4: Testing mise configuration ==="

if [ -n "$REPO_URL" ]; then
    echo "→ Cloning repository into VM..."

    ssh_to_vm << REMOTE_SCRIPT
set -euo pipefail
export PATH="\$HOME/.local/bin:\$PATH"

echo "→ Cloning repository..."
git clone $REPO_URL /tmp/dev-env-test
cd /tmp/dev-env-test

echo "→ Running mise install..."
mise install

echo ""
echo "=== Installed Tools ==="
mise list

echo ""
echo "=== Tool Versions ==="
mise where java 2>/dev/null && java -version 2>&1 || echo "Java: not installed"
mise where go 2>/dev/null && go version 2>&1 || echo "Go: not installed"
mise where terraform 2>/dev/null && terraform version 2>&1 | head -1 || echo "Terraform: not installed"
mise where kubectl 2>/dev/null && kubectl version --client 2>&1 || echo "kubectl: not installed"
mise where helm 2>/dev/null && helm version --short 2>&1 || echo "Helm: not installed"

echo ""
echo "✓ Mise install completed successfully"
REMOTE_SCRIPT
else
    echo "⚠️  Skipping repo clone (no git remote found)"
    echo "→ Testing mise installation only..."

    ssh_to_vm << 'REMOTE_SCRIPT'
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

echo "→ Mise version:"
mise --version

echo "✓ Mise is functional"
REMOTE_SCRIPT
fi

# --- Step 5: Summary ---
echo ""
echo "=== Test Complete ==="
echo "✓ VM: $VM_NAME"
echo "✓ macOS: $MACOS_VERSION"
echo "✓ Mise installation: Success"
echo ""
echo "The VM will now be cleaned up automatically."
echo "To skip cleanup, remove the trap command from this script."
