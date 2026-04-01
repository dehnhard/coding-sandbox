# Coding Sandbox

Isolated coding environments with AI tools (Claude Code, OpenCode, Crush, Qwen Code) on Debian 13, powered by [Incus](https://linuxcontainers.org/incus/).

## Features

Three modes of operation via two scripts:

- **Container mode** (`coding-sandbox`)
  - Needs to build the images before the first run (requires sudo)
  - Ephemeral container that mounts your current directory from the host.
  - The configuration (the sandbox users home directory) is stored in the host users `~/.coding-sandbox` directory.
- **VM mode** (`coding-sandbox --vm`) 
  - Needs the same build step as the containert above (that build creates images for the VM an the container)
  - It starts a Persistent VM once where you check out and work on projects directly.
    - Every subsequent access is a new shell inside the same VM 
  - All data code and configuration is isolated on the VM disk, not the host.
    - Keep in mind that a rebuild of the VM will destroy all data inside!
    - The idea is to checkout projects into the VM, work on them directly and push all work back into the repo.
- **Quick sandbox** (`quick-coding-sandbox`)
  - This lightweight variant skips the custom image build and uses stock Debian images from Incus.
  - On first run or setup (`quick-coding-sandbox setup`) you can select which tool(s) to install.
  - Ephemeral container that mounts your current directory from the host.
  - The configuration (the sandbox users home directory) is stored in the host users `~/.quick-coding-sandbox` directory.

- AI Coding tools (the unified installation scripts for these tools are in the `tools` subdirectory)
  - [Claude Code](https://claude.ai) (default)
  - [OpenCode](https://github.com/anomalyco/opencode)
  - [Crush](https://github.com/charmbracelet/crush)
  - [Qwen Code](https://github.com/QwenLM/qwen-code)
  
## State of the Project

- This project is Beta quality. It's quite stable for me and my current work style, but expect rough edges for other usages.
  - I'm open to feedback and suggestions. 
- I'll continue to experiment, the different sandbox modes might change in the future.
  - I'm happy to hear about your use cases. 

## Installation

### From .deb package (recommended)

```bash
# Build the package
make deb
sudo dpkg -i coding-sandbox_*.deb
```

### From source

```bash
# Just run directly from the repo
./coding-sandbox build
./coding-sandbox shell
```

## Quick Start

```bash
# Build the image (once, requires root for distrobuilder)
coding-sandbox build

# Option A: Ephemeral container — mounts $PWD, destroyed on exit
cd ~/projects/my-repo
coding-sandbox claude

# Option B: Persistent VM — clone repos inside, work directly
coding-sandbox --vm shell
git clone git@github.com:you/project.git
cd project && claude
```

## Prerequisites for `coding-sandbox`

- [Incus](https://linuxcontainers.org/incus/docs/main/installing/) installed and initialized (`incus init`)
- User is member of the incus group
- [distrobuilder](https://linuxcontainers.org/distrobuilder/introduction/) (for image builds, requires root)
- debootstrap (for Debian rootfs bootstrapping during build)
- APT proxy (apt-cacher-ng) recommended for fast repeated builds

## APT Proxy Setup

For faster repeated builds, install apt-cacher-ng and configure it on your host:

```bash
sudo apt install apt-cacher-ng
```

The build script automatically detects if `Acquire::https::Proxy` is configured and uses it. No further configuration needed.

If you skip this, builds will work but download all packages from Debian mirrors each time.

## VM vs Container

| | VM (`--vm`) | Container (default) |
|---|---|---|
| **Startup** | 30–180s | 1–5s |
| **Persistence** | Survives reboots, lives until `destroy` | Destroyed on exit |
| **Workspace** | Clone projects inside the VM | `$PWD` mounted from host |
| **Home directory** | On VM disk | Persistent on host (`~/.coding-sandbox/home`) |
| **Isolation** | Full kernel (own kernel, GRUB, ACPI) | Shared host kernel |
| **Host sync** | Timezone, locale, APT proxy, git config | Git config (first run) |
| **Use case** | Long-running dev environment | Quick one-off tasks, CI-like runs |

## Commands

```
coding-sandbox [command] [--vm]

shell       Interactive shell (default)
build       Build container and VM images
start       Start the VM (VM only)
stop        Stop the VM (VM only)
destroy     Delete the VM and images [--purge to delete build cache]
rebuild     Destroy and rebuild from scratch [--purge to force full rebuild]
status      Show instance and image status (with version freshness)
doctor      System diagnostics and dependency check
version     Show version
help        Show this help
```

Add `--vm` to use VM mode instead of container mode.

## Configuration

All settings are configurable via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `CODING_SANDBOX_VM` | `coding-sandbox` | VM instance name |
| `CODING_SANDBOX_IMAGE` | `coding-sandbox/debian-13` | VM image alias |
| `CODING_SANDBOX_CONTAINER_IMAGE` | `coding-sandbox/debian-13/container` | Container image alias |
| `CODING_SANDBOX_BUILDDIR` | `~/.cache/coding-sandbox` (dev) / `/var/cache/coding-sandbox` (.deb) | Build artifact directory |
| `CODING_SANDBOX_TOOLS` | `claude-code opencode crush` | Tools to install during build |
| `CODING_SANDBOX_PORTS` | *(empty)* | Space-separated ports to forward (localhost-only) |
| `CODING_SANDBOX_USER` | `sandbox` | User inside VM/container |
| `CODING_SANDBOX_CPU` | `1` | VM vCPU count |
| `CODING_SANDBOX_RAM` | `2GiB` | VM RAM allocation |
| `CODING_SANDBOX_DISK` | `20GiB` | VM root disk size |
| `CODING_SANDBOX_HOME` | `~/.coding-sandbox/home` | Container persistent home |

## What's in the Image

- **OS**: Debian 13 (Trixie) amd64 with systemd
- **AI Tools**: [Claude Code](https://claude.ai), [OpenCode](https://github.com/anomalyco/opencode), [Crush](https://github.com/charmbracelet/crush), [Qwen Code](https://github.com/QwenLM/qwen-code) (configurable via `CODING_SANDBOX_TOOLS`)
- **Dev Tools**: jq, gh (GitHub CLI), glow, bat, ncdu, ripgrep, fzf, shellcheck
- **Essentials**: git, vim, nano, curl, wget, htop, SSH server
- **User**: `sandbox` with passwordless sudo

## First-Time Setup

Both AI tools need to be configured on first use (in either VM or container):

- **Claude Code**: Run `claude` and follow the login prompt, or run `claude login` beforehand. See [Claude Code docs](https://docs.anthropic.com/en/docs/claude-code) for details.
- **OpenCode**: Requires a configuration file (`~/.config/opencode/config.json`) with your provider and API key. See [OpenCode README](https://github.com/anomalyco/opencode) for setup instructions.
- **Crush**: See [Crush README](https://github.com/charmbracelet/crush) for configuration.
- **Qwen Code**: Run `qwen` and follow the setup prompt, or set API key via environment variable.

In containers, credentials persist in the shared home directory (`~/.coding-sandbox/home`) across runs. In the VM, they persist on the VM disk.

### Uninstalling Tools in the VM

Each tool generates an uninstaller script at `/usr/local/lib/uninstallers/<tool-name>` inside the VM. To manually uninstall a tool:

```bash
# Inside the VM (via coding-sandbox --vm shell)
sudo /usr/local/lib/uninstallers/claude-code

# Or from the host
incus exec coding-sandbox -- /usr/local/lib/uninstallers/claude-code
```

Running `coding-sandbox --vm update` automatically uses uninstallers for clean tool updates.

## Quick Coding Sandbox

For lightweight containers without custom image builds:

```bash
quick-coding-sandbox setup   # install tools (one-time)
quick-coding-sandbox shell   # launch container
```

Uses stock Debian images from Incus image server — no root, no distrobuilder needed. A `sandbox` user (UID 1000, passwordless sudo) is created inside the container at launch, matching the behavior of `coding-sandbox`.

### Incus 6.0.x UID Mapping

If you are **not** in the `incus-admin` group and use Incus 6.0.x LTS (Debian Trixie/Sid) with an `incus-user` restricted project, container launches will fail because `shift=true` is blocked in restricted projects. This affects `coding-sandbox` without `--vm` and `quick-coding-sandbox`. VM mode is not affected.

Users in the `incus-admin` group are not affected — they operate in the unrestricted `default` project where `shift=true` works directly.

**Workaround 1: Configure the restricted project (recommended)**

Ask your administrator (or run with sudo yourself) to allow UID mapping in your project:

```bash
# Replace user-1000 with your project name (incus project list to check)
sudo incus project set user-1000 restricted.containers.lowlevel=allow
sudo incus project set user-1000 restricted.idmap.uid=1000
sudo incus project set user-1000 restricted.idmap.gid=1000

# Allow the UID mapping at OS level (if not already present)
echo "root:1000:1" | sudo tee -a /etc/subuid
echo "root:1000:1" | sudo tee -a /etc/subgid
```

This allows the scripts to fall back to `raw.idmap` when `shift=true` is blocked. The `/etc/subuid` and `/etc/subgid` entries permit the kernel to map host UID/GID 1000 into the container namespace. This is a minimal, targeted entry — it does not change host permissions or grant new privileges to any user. The security impact is comparable to `shift=true` (container processes with the mapped UID can access the host user's mounted files, which is the intended behavior).

**Workaround 2: Use the incus-admin group**

```bash
sudo usermod -aG incus-admin $USER
# Log out and back in for group change to take effect
```

Members of `incus-admin` operate in the unrestricted `default` project where `shift=true` works without issues. This is the simpler option but grants full Incus administrative privileges.

**Future:** Once Debian stable ships an Incus version that handles UID mapping in restricted projects without these workarounds, this section and the related fallback code can be removed.

## Port Forwarding

Forward ports from container/VM to host (localhost-only):

```bash
CODING_SANDBOX_PORTS="8080 3000" coding-sandbox shell
```

## Usability Tips

- **Images**: First build takes 10-30 minutes. Subsequent rebuilds reuse debootstrap cache.
- **Chrome integration**: Use `--remote-debugging-port=9222` inside the sandbox, forward port 9222.
- **Custom tools**: Set `CODING_SANDBOX_TOOLS="claude-code crush"` to control which tools are installed (default: all).

## Testing

```bash
# Run unit tests
bash tests/run.sh

# Run unit + integration tests (requires Incus, creates/destroys instances)
bash tests/run.sh --integration
```
