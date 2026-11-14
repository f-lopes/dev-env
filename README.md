# dev-env

Development environment configuration managed by [mise](https://mise.jdx.dev/).

## Setup

On a fresh macOS machine:

1. Install mise: `curl https://mise.run | sh`
2. Clone this repository, `cd` into it and run `mise trust .`
3. Bootstrap everything: `mise bootstrap --yes`. Preview it first with
   `mise bootstrap --dry-run`.
4. Open a new terminal so the managed `~/.zprofile` and `~/.zshrc` load.
5. Set up 1Password (see [1Password](#1password)), then run `chezmoi apply`
   to render the 1Password-backed dotfiles.

`mise bootstrap` installs the system packages, runs the post-package hooks
(Oh My Zsh, Nerd Fonts), clones the dotfiles repository, sets zsh as the login
shell, installs this repository's tools, applies the dotfiles with chezmoi and
finally installs the global tools from `~/.config/mise/config.toml`.
See [fresh-test.md](fresh-test.md) for a step-by-step walkthrough.

## Tools

Each tool is declared in exactly one of three layers:

| Layer | Declared in | Examples |
|-------|-------------|----------|
| 1. System and GUI packages | `[bootstrap.packages]` in this repository's `.mise.toml` (Homebrew) | git, zsh, op, OrbStack (docker, docker-compose), Vagrant, Raycast |
| 2. Global CLI tools | `~/.config/mise/config.toml`, managed by the [dotfiles](https://github.com/f-lopes/dotfiles) repository | Java, Maven, kubectl, Helm, Terraform, Node |
| 3. Per-project overrides | each project's own `.mise.toml` | `java = "corretto-21"`, `node = "22"` |

Layers 1 and 2 are available from any directory. A project's `.mise.toml`
overrides a global version only inside that project, for example:

```toml
# ~/work/git/my-project/.mise.toml
[tools]
java = "corretto-21"
```

All layers share mise's data directory, so nothing is downloaded twice.

### Global Tools (`~/.config/mise/config.toml`)
| Tool | Version | Backend |
|------|---------|---------|
| Java (Amazon Corretto) | corretto-17 (default), corretto-21, corretto-25 | Core |
| Maven | 3.9.9 | Core |
| Go | 1.21 | Core |
| Node | 26 (latest LTS line; needed by `npm:` tools) | Core |
| Terraform | latest | Core |
| CMake | latest | Core |
| Starship | latest | Core |
| ripgrep | latest | Core |
| bat | latest | Core |
| GitHub CLI (gh) | latest | Core |
| chezmoi | latest | Core |
| fzf, fd, just, task, lazygit | latest | Aqua |
| zellij, zoxide | latest | Aqua |
| kubectl, helm, k9s, kubectx, sops | latest | Aqua |
| kind, skaffold, trivy, infracost | latest | Aqua |
| shellcheck | latest | Aqua |
| httpie-go | latest | Aqua |
| Junie CLI | latest | npm |

The first Java version in the list is the global default. All three are
installed, so a project can switch to another one without a download.

### This Repository's Tools (`.mise.toml`)
| Tool | Purpose |
|------|---------|
| chezmoi | Applies the dotfiles during bootstrap |
| gitleaks | Secret scanning for the pre-commit hook |

### System Packages (via `mise bootstrap`)

**macOS (Homebrew):**
- zsh, git, htop
- **Vagrant**: Homebrew cask
- **OrbStack**: replaces Docker Desktop and provides the `docker` and
  `docker-compose` CLIs (linked on the app's first launch)
- **Raycast**: macOS launcher app
- **1Password** and **1Password CLI**: the app and the `op` command
- **Ghostty**: modern terminal emulator

**Linux (apt):**
- zsh, git, curl, htop, vagrant
- **docker-ce**: Docker runtime (OrbStack is macOS-only)
- build-essential, sudo, software-properties-common, acl

### Bootstrap Repos, Login Shell and Hooks
- **`[bootstrap.repos]`** clones `https://github.com/f-lopes/dotfiles.git`
  into `~/.local/share/chezmoi`. Override it with the `CHEZMOI_DOTFILES_REPO`
  env var.
- **`[bootstrap.user]`** sets zsh as the login shell.
- **post-packages hook** installs Oh My Zsh and, on macOS, the Hack and
  JetBrains Mono Nerd Fonts (non-fatal).
- **post-tools hook** loads Homebrew's environment, checks that 1Password is
  usable, runs `chezmoi apply` against the cloned source, then runs
  `mise install` from `$HOME` to install the global tools.

### 1Password

Some dotfiles (currently `~/.ssh/config`) read values from 1Password with the
`op` CLI. On a fresh machine 1Password is not signed in yet, so the post-tools
hook skips those parts (it sets `CHEZMOI_SKIP_1PASSWORD=1`) instead of
failing, and prints what to do. To finish:

1. Open the 1Password app and sign in.
2. Enable **Settings → Developer → Integrate with 1Password CLI**.
3. Run `chezmoi apply`.

### Excluded Tools
| Tool | Reason |
|------|--------|
| Python | Will use Docker |
| Ansible | Will use Docker |
| tmux | Replaced by zellij |
| SDKMAN | Replaced by mise Java management |

### GUI Apps (manual install)
| App | Install Command |
|-----|-----------------|
| Warp | `brew install --cask warp` (its Homebrew download currently returns 404) |

## Secret Scanning

[gitleaks](https://github.com/gitleaks/gitleaks) scans for secrets with its
default rules, configured in `.gitleaks.toml`.

- **Pre-commit hook:** enable it once per clone with
  `git config core.hooksPath .githooks`. It scans staged changes and blocks
  the commit if it finds a secret. Bypass once with `git commit --no-verify`.
- **CI:** `.github/workflows/ci.yml` scans the full history on pushes to
  `main` and on pull requests, and also runs shellcheck and a bootstrap
  dry-run.
- **False positives:** add a `# gitleaks:allow` comment on the line rather
  than allowlisting a whole file.

> 💡 **Tip:** Use [tart.run](#testing-with-tart-run) to test the bootstrap in a clean, isolated macOS VM. The VM clones both repositories from GitHub, so push your changes first.

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
   that `chezmoi source-path` resolves, that the global tools (`java`, `mvn`,
   `kubectl`, `node`, `starship`, `zellij`, `chezmoi`, `op`, `git`) resolve in
   a login shell, that `java`, `mvn` and `kubectl` also resolve in a
   non-interactive login shell, that `~/.ssh/config` was rendered (without the
   1Password hosts, since the VM has no account), and that the login shell is
   zsh. `docker` is not checked, because OrbStack only links its CLI on the
   app's first launch.
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
