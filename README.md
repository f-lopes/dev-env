# dev-env

Development environment configuration managed by [mise](https://mise.jdx.dev/).

## Setup

On a fresh machine, two commands are enough:

1. Install mise: `curl https://mise.run | sh`
2. Bootstrap everything: `mise bootstrap`

`mise bootstrap` installs the system packages, runs the post-package hooks
(Oh My Zsh, Nerd Fonts), clones the dotfiles repository, sets zsh as the login
shell, installs the tools, and finally applies the dotfiles with chezmoi.
Preview it first with `mise bootstrap --dry-run`.

## Tools

Tools are split across two manifests:

- **`~/.config/mise/config.toml`** (managed by
  [chezmoi dotfiles](https://github.com/f-lopes/dotfiles)) is the source of
  truth for everyday tools and is available from any directory.
- **`.mise.toml`** in this repository holds the bootstrap configuration and the
  heavy, project-scoped tools.

Both share mise's default data directory, so nothing is downloaded twice.

### Everyday Tools (global config)
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
| fzf, fd, just, task, lazygit | latest | Aqua |
| zellij, zoxide | latest | Aqua |
| kubectl, helm, k9s, kubectx, sops | latest | Aqua |
| shellcheck | latest | Aqua |
| httpie-go | latest | Aqua |

### Project-Scoped Tools (`.mise.toml`)
| Tool | Description |
|------|-------------|
| chezmoi | Dotfiles manager (also global; needed to bootstrap) |
| CMake | Build system generator |
| kind | Kubernetes in Docker (local clusters) |
| skaffold | Kubernetes dev workflow |
| trivy | Container security scanning |
| infracost | Terraform cost estimates |
| Junie CLI | npm:@jetbrains/junie-cli (allow_low_downloads) |

### System Packages (via `mise bootstrap`)

**macOS (Homebrew):**
- zsh, git, htop
- **Vagrant** — installed as a Homebrew cask
- **OrbStack** — replaces Docker Desktop; bundles Docker CLI
- **Raycast** — macOS launcher app
- **1Password CLI** — password manager CLI (provides `op` command)
- **Ghostty** — modern terminal emulator
- **Warp** — modern GPU-accelerated terminal

**Linux (apt):**
- zsh, git, curl, htop, vagrant
- **docker-ce** — Docker runtime (OrbStack is macOS-only)
- build-essential, sudo, software-properties-common, acl

### Bootstrap Repos, Login Shell and Hooks
- **`[bootstrap.repos]`** — clones `https://github.com/f-lopes/dotfiles.git`
  into `~/.local/share/chezmoi` (override with the `CHEZMOI_DOTFILES_REPO` env
  var)
- **`[bootstrap.user]`** — sets zsh as the login shell
- **post-packages hook** — Oh My Zsh, plus Hack & JetBrains Mono Nerd Fonts on
  macOS (non-fatal)
- **post-tools hook** — `chezmoi apply` against the cloned source

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

# Show the available options
./scripts/test-mise-tart.sh --help
```

The flag and the macOS version can be given in any order.

The script will:
1. Clone and run an ephemeral macOS VM
2. Wait for SSH to become available
3. Install mise inside the VM
4. Clone this repository and run `mise bootstrap --yes`
5. Assert that `~/.zshrc` and the `~/.config/zsh/zsh.d/` fragments were applied,
   that `chezmoi source-path` resolves, that `java`, `kubectl`, `starship`,
   `zellij` and `chezmoi` resolve in a login shell, and that the login shell is
   zsh
6. Run `mise bootstrap` a second time to verify idempotency
7. Clean up the VM automatically, unless `--no-cleanup` is given

The script exits with the remote commands' exit code, so a failed bootstrap or
assertion fails the run.

**Requirements:**
- `tart` CLI installed
- `sshpass` installed (`brew install sshpass`)
- A git remote named `origin`, or `MISE_TEST_REPO` set — the script exits with
  an error otherwise. An `scp`-style GitHub remote is rewritten to HTTPS,
  because a fresh VM has no SSH keys.

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
sshpass -p admin ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@"$VM_IP" 'git clone <your-repo-url> /tmp/dev-env && cd /tmp/dev-env && ~/.local/bin/mise trust . && ~/.local/bin/mise bootstrap --yes && ~/.local/bin/mise doctor'
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
