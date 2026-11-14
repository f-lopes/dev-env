#!/usr/bin/env bash
#
# test-mise-tart.sh — Test the mise development environment in an ephemeral macOS VM
#
# Usage:
#   ./scripts/test-mise-tart.sh [-n|--no-cleanup] [tahoe|golden-gate]
#
# Examples:
#   ./scripts/test-mise-tart.sh                 # Defaults to macOS 26 (Tahoe)
#   ./scripts/test-mise-tart.sh golden-gate     # macOS 27 (Golden Gate)
#   ./scripts/test-mise-tart.sh tahoe           # macOS 26 (Tahoe)
#   ./scripts/test-mise-tart.sh -n golden-gate  # Keep the VM running afterwards
#
# Requirements:
#   - tart CLI installed (https://tart.run)
#   - sshpass installed (`brew install sshpass`)
#
# What it does:
#   1. Clones and runs an ephemeral macOS VM
#   2. Waits for SSH to become available (uses default admin/admin credentials)
#   3. Installs mise inside the VM
#   4. Clones this repository and runs `mise bootstrap --yes` (packages, hooks,
#      repos, login shell, tools)
#   5. Asserts the dotfiles were applied and the global tools resolve in
#      interactive and non-interactive login shells
#   6. Re-runs `mise bootstrap --yes` to check idempotency
#   7. Cleans up the VM after testing, unless --no-cleanup is given
#

set -euo pipefail

# --- Configuration ---
VM_NAME="mise-test-$(date +%Y%m%d-%H%M%S)"
MEMORY_MB=16384  # 16 GB in megabytes
TIMEOUT=600  # Max seconds to wait for SSH
SSH_USER="admin"
SSH_PASS="admin"  # gitleaks:allow — default password for ephemeral Cirrus Labs base images

# --- Argument parsing ---
NO_CLEANUP="${NO_CLEANUP:-0}"
MACOS_VERSION=""

usage() {
    cat <<'USAGE'
Usage: ./scripts/test-mise-tart.sh [-n|--no-cleanup] [tahoe|golden-gate]

Options:
  -n, --no-cleanup  Keep the VM running after the test and print SSH details
  -h, --help        Show this help and exit

Arguments:
  tahoe | macos26 | 26        macOS 26 (Tahoe), the default
  golden-gate | macos27 | 27  macOS 27 (Golden Gate)
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--no-cleanup)
            NO_CLEANUP=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "❌ Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            if [ -n "$MACOS_VERSION" ]; then
                echo "❌ Unexpected argument: $1" >&2
                usage >&2
                exit 1
            fi
            MACOS_VERSION="$1"
            ;;
    esac
    shift
done

MACOS_VERSION="${MACOS_VERSION:-tahoe}"
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
        echo "❌ Unknown macOS version: $MACOS_VERSION" >&2
        echo "   Supported: tahoe, golden-gate" >&2
        exit 1
        ;;
esac

# Check for required host tools
for required in tart sshpass; do
    if ! command -v "$required" >/dev/null 2>&1; then
        echo "❌ $required is not installed. Install it with: brew install $required" >&2
        exit 1
    fi
done

# Repo URL: MISE_TEST_REPO wins, otherwise the checkout's origin remote.
# A fresh VM has no SSH keys, so an scp-style GitHub remote is rewritten to HTTPS.
REPO_URL="${MISE_TEST_REPO:-$(cd "$(dirname "$0")/.." && git remote get-url origin 2>/dev/null || true)}"
if [ -z "$REPO_URL" ]; then
    echo "❌ No repository URL available." >&2
    echo "   Configure a git remote named 'origin' or set MISE_TEST_REPO." >&2
    exit 1
fi
case "$REPO_URL" in
    git@github.com:*)
        REPO_URL="https://github.com/${REPO_URL#git@github.com:}"
        echo "→ Rewrote SSH remote to HTTPS for the VM: $REPO_URL"
        ;;
esac

# --- Helper Functions ---
# shellcheck disable=SC2329  # invoked indirectly via `trap cleanup EXIT`
cleanup() {
    echo ""
    if [ "$NO_CLEANUP" = "1" ]; then
        echo "=== Cleanup skipped (--no-cleanup) ==="
        echo "→ VM name: $VM_NAME"
        echo "→ VM IP:   $(tart ip "$VM_NAME" 2>/dev/null || echo 'unavailable')"
        echo "→ SSH:     ssh ${SSH_USER}@$(tart ip "$VM_NAME" 2>/dev/null || echo '<ip>')  (password: ${SSH_PASS})"
        echo "→ Remove it later with: tart stop '$VM_NAME' && tart delete '$VM_NAME'"
        return 0
    fi
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

# Run a script fed on stdin inside the VM, with REPO_URL exported there.
# The heredoc stays quoted; only this assignment is expanded on the host.
ssh_script() {
    ssh_to_vm "REPO_URL=$(printf '%q' "$REPO_URL") bash -s"
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

# --- Step 4: Clone repo, bootstrap and assert ---
echo ""
echo "=== Step 4: Bootstrapping the machine from .mise.toml ==="

echo "→ Cloning repository into VM: $REPO_URL"

REMOTE_STATUS=0
ssh_script << 'REMOTE_SCRIPT' || REMOTE_STATUS=$?
set -euo pipefail
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

fail() {
    echo "❌ $1" >&2
    exit 1
}

echo "→ Cloning repository..."
rm -rf /tmp/dev-env-test
git clone "$REPO_URL" /tmp/dev-env-test
cd /tmp/dev-env-test

echo "→ Trusting the config..."
mise trust .

echo "→ Running mise bootstrap..."
mise bootstrap --yes

echo ""
echo "=== Assertions ==="

[ -f "$HOME/.zshrc" ] || fail "~/.zshrc was not created by chezmoi"
echo "✓ ~/.zshrc exists"

shopt -s nullglob
fragments=("$HOME/.config/zsh/zsh.d/"*.zsh)
shopt -u nullglob
[ "${#fragments[@]}" -gt 0 ] || fail "no zsh fragments under ~/.config/zsh/zsh.d/"
echo "✓ ${#fragments[@]} zsh fragments applied"

chezmoi source-path >/dev/null 2>&1 || fail "chezmoi source-path does not resolve"
echo "✓ chezmoi source path: $(chezmoi source-path)"

# Global tools: mise global config (java, mvn, kubectl, node, ...) and
# Homebrew (op, git). docker is not checked: OrbStack only links its CLI on
# first app launch, which a headless VM never does.
for tool in java mvn kubectl node starship zellij chezmoi op git; do
    zsh -lic "command -v $tool" >/dev/null 2>&1 || fail "$tool does not resolve in a login shell"
    echo "✓ $tool resolves in a login shell"
done

# The same tools must resolve without an interactive shell (IDEs, zsh -l -c),
# which relies on the mise shims added by ~/.zprofile.
for tool in java mvn kubectl; do
    zsh -lc "command -v $tool" >/dev/null 2>&1 || fail "$tool does not resolve in a non-interactive login shell"
    echo "✓ $tool resolves in a non-interactive login shell"
done

# A fresh VM has no 1Password account, so the bootstrap must skip the
# 1Password-backed SSH hosts instead of failing.
[ -f "$HOME/.ssh/config" ] || fail "~/.ssh/config was not created by chezmoi"
if grep -q '^Host ' "$HOME/.ssh/config"; then
    echo "✓ ~/.ssh/config rendered with 1Password hosts"
else
    echo "✓ ~/.ssh/config rendered without 1Password hosts (no account configured)"
fi

login_shell=$(dscl . -read "$HOME" UserShell 2>/dev/null | awk '{print $2}')
case "$login_shell" in
    *zsh) echo "✓ login shell is $login_shell" ;;
    *) fail "login shell is '$login_shell', expected zsh" ;;
esac

echo ""
echo "=== Idempotency: second bootstrap run ==="
mise bootstrap --yes

repo_count=$(git -C "$HOME/.local/share/chezmoi" rev-parse --is-inside-work-tree 2>/dev/null || echo 'false')
[ "$repo_count" = "true" ] || fail "dotfiles checkout is not a git work tree after the second run"
echo "✓ dotfiles checkout intact after the second bootstrap"

echo ""
echo "=== Installed Tools ==="
mise list

echo ""
echo "✓ Bootstrap completed successfully"
REMOTE_SCRIPT

# --- Step 5: Summary ---
echo ""
if [ "$REMOTE_STATUS" -eq 0 ]; then
    echo "=== Test Complete ==="
    echo "✓ VM: $VM_NAME"
    echo "✓ macOS: $MACOS_VERSION"
    echo "✓ Bootstrap and assertions: Success"
else
    echo "=== Test Failed ==="
    echo "❌ Remote commands exited with status $REMOTE_STATUS"
fi

exit "$REMOTE_STATUS"
