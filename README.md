# dev-env

Development environment configuration managed by [mise](https://mise.jdx.dev/).

## Setup

1. Install mise: `curl https://mise.run | sh`
2. Install system packages: `mise bootstrap apply`
3. Install tools: `mise install`
4. Apply environment: `mise env --activate`

## Tools

All development tools are defined in `.mise.toml`. The configuration includes:

### Core Tools
| Tool | Version | Backend |
|------|---------|---------|
| Java (Amazon Corretto) | corretto-17 | Core |
| Maven | 3.9.9 | Core |
| Go | 1.21 | Core |
| Terraform | latest | Core |
| Starship | latest | Core |
| ripgrep | latest | Core |
| bat | latest | Core |
| GitHub CLI (gh) | latest | Core |
| chezmoi | latest | Core |
| CMake | latest | Core |

### CLI Utilities (Aqua registry)
| Tool | Description |
|------|-------------|
| fzf | Command-line fuzzy finder |
| just | Command runner (justfile) |
| task (go-task) | Task runner / Makefile alternative |
| 1Password CLI | Password manager CLI (via Homebrew cask) |
| fd | Find alternative |
| lazygit | Terminal UI for git |
| zellij | Terminal multiplexer (replaces tmux) |
| zoxide | Smart cd command |

### Kubernetes & DevOps (Aqua registry)
| Tool | Description |
|------|-------------|
| kubectl | Kubernetes CLI |
| helm | Kubernetes package manager |
| k9s | Kubernetes cluster UI |
| kind | Kubernetes in Docker (local clusters) |
| skaffold | Kubernetes dev workflow |
| kubectx | Kubernetes context/namespace switcher |
| sops | Encrypted secrets management |
| infracost | Terraform cost estimates |
| shellcheck | Shell script linting |
| trivy | Container security scanning |

### Other Backends
| Tool | Backend |
|------|---------|
| Junie CLI | npm:@jetbrains/junie-cli (allow_low_downloads) |
| httpie-go | aqua:nojima/httpie-go (Go-based, no Python needed) |

### System Packages (via `mise bootstrap apply`)

**macOS (Homebrew):**
- zsh, git, htop, vagrant
- **OrbStack** — replaces Docker Desktop; bundles Docker CLI
- **Raycast** — macOS launcher app
- **1Password CLI** — password manager CLI (provides `op` command)
- **Ghostty** — modern terminal emulator
- **Warp** — modern GPU-accelerated terminal

**Linux (apt):**
- zsh, git, curl, htop, vagrant
- **docker-ce** — Docker runtime (OrbStack is macOS-only)
- build-essential, sudo, software-properties-common, acl

### Post-Install Scripts
- **Oh My Zsh** — auto-installed with default config
- **Nerd Fonts** — Hack & JetBrains Mono (macOS only)
- **chezmoi dotfiles** — initializes from `https://github.com/f-lopes/dotfiles.git` (override with `CHEZMOI_DOTFILES_REPO` env var)

### Excluded Tools
| Tool | Reason |
|------|--------|
| Python | Will use Docker |
| Ansible | Will use Docker |
| tmux | Replaced by zellij |
| SDKMan | Replaced by mise Java management |

### GUI Apps (manual install)
| App | Install Command |
|-----|-----------------|
| Ghostty | `brew install --cask ghostty` |
| Warp | `brew install --cask warp` |

> 💡 **Tip:** Use [tart.run](#testing-with-tart-run) to test your `.mise.toml` configuration in a clean, isolated macOS VM before committing changes.

## Testing with tart.run

Test your mise setup in an ephemeral macOS VM using [tart.run](https://tart.run).

### Automated Test Script

The easiest way to test is using the provided shell script:

```bash
# Test on macOS 26 (Tahoe) — default
./scripts/test-mise-tart.sh

# Test on macOS 27 (Golden Gate)
./scripts/test-mise-tart.sh golden-gate

# Keep the VM running after the test (for manual inspection)
./scripts/test-mise-tart.sh --no-cleanup
./scripts/test-mise-tart.sh -n golden-gate
```

The script will:
1. Clone and run an ephemeral macOS VM
2. Wait for SSH to become available
3. Install mise inside the VM
4. Clone this repository and run `mise install`
5. Report installed tools and their versions
6. Clean up the VM automatically

**Requirements:**
- `tart` CLI installed
- `sshpass` installed (`brew install sshpass`)
- Git remote configured (or set `MISE_TEST_REPO` env var)

### Accessing the VM via SSH

When you run the script with `--no-cleanup` (`-n`), the VM stays running after the test finishes. The script prints the VM's IP address and SSH credentials at the end.

To SSH into the VM interactively:

```bash
# Get the VM's IP address
VM_IP=$(tart ip "$VM_NAME")

# Connect via SSH
ssh admin@"$VM_IP"
# Password: admin
```

The Cirrus Labs base images use default credentials `admin`/`admin`. The VM name is printed by the script (e.g., `mise-test-20261107-164500`). You can also list running VMs with `tart list`.

To clean up manually after you're done:

```bash
tart stop "$VM_NAME"
tart delete "$VM_NAME"
```

### Accessing the VM GUI

You can access the VM's graphical desktop, similar to a Parallels VM. There are two methods:

#### Method 1: Tart's built-in VNC (recommended)

Run the VM with the `--vnc-experimental` flag instead of `--no-graphics`:

```bash
tart run "$VM_NAME" --vnc-experimental
```

This opens a Tart window showing the VM's desktop. You can interact with it directly, just like a native macOS window.

#### Method 2: macOS Screen Sharing

The Cirrus Labs base images have Screen Sharing (VNC) enabled by default on port 5900. Connect using any VNC client:

```bash
# Using macOS built-in Screen Sharing
open "vnc://$(tart ip "$VM_NAME")"

# Or using a VNC client like RealVNC, TigerVNC, etc.
# Connect to: $(tart ip "$VM_NAME")
# Username: admin
# Password: admin
```

#### Using the test script with GUI

To keep the VM running with GUI access for manual inspection:

```bash
# Start the VM with GUI access instead of headless
tart run "$VM_NAME" --vnc-experimental &

# Then run the test script steps manually, or use --no-cleanup and connect via VNC after
./scripts/test-mise-tart.sh --no-cleanup
```

### Manual One-Liners

Alternatively, you can run the VM manually:

#### macOS 27 (Golden Gate)

```bash
VM_NAME="mise-test"
tart clone ghcr.io/cirruslabs/macos-golden-gate-base "$VM_NAME"
tart set "$VM_NAME" --memory 16384
tart run "$VM_NAME" --no-graphics &
```

#### macOS 26 (Tahoe)

```bash
VM_NAME="mise-test"
tart clone ghcr.io/cirruslabs/macos-tahoe-base "$VM_NAME"
tart set "$VM_NAME" --memory 16384
tart run "$VM_NAME" --no-graphics &
```

#### Testing mise in the VM

The Cirrus Labs base images use default credentials `admin`/`admin` for SSH. Install `sshpass` for non-interactive password auth: `brew install sshpass`.

1. Run one of the commands above to start an ephemeral VM.
2. Wait for SSH to be ready, then execute commands:

```bash
# Get the VM's IP
VM_IP=$(tart ip "$VM_NAME")

# Wait for SSH (uses admin/admin password)
while ! sshpass -p admin ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@"$VM_IP" 'echo ready' 2>/dev/null; do sleep 5; done

# Install mise
sshpass -p admin ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@"$VM_IP" 'curl https://mise.run | sh'

# Verify installation
sshpass -p admin ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@"$VM_IP" '~/.local/bin/mise doctor'

# Clone and test (replace with your repo URL)
sshpass -p admin ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@"$VM_IP" 'git clone <your-repo-url> /tmp/dev-env && cd /tmp/dev-env && ~/.local/bin/mise install && ~/.local/bin/mise doctor'
```

3. Or SSH interactively:

```bash
ssh admin@$(tart ip "$VM_NAME")
# Password: admin
```

4. When finished, delete the VM to free resources:

```bash
tart delete "$VM_NAME"
```
