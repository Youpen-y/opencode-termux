# opencode-termux

An installer script for running [opencode](https://github.com/anomalyco/opencode) on Termux.

## How It Works

opencode is a Go binary compiled against Linux glibc, which cannot run directly on Termux (Bionic libc). This script leverages the official Termux glibc subsystem to provide a compatible runtime.

### Key Components

| Component | Description |
|-----------|-------------|
| `glibc-repo` | Termux's glibc package repository |
| `glibc-runner` | Provides the `grun` command to launch glibc binaries in Termux |

### How `grun` Works

1. `unset LD_PRELOAD` — avoids conflicts between Termux's `termux-exec` and glibc
2. Launches the target binary via glibc's `ld.so`
3. Automatically sets the correct library search paths

> **NOTE:** Do NOT use `grun --configure` — it uses `patchelf` to modify the binary, which causes segfaults with Go binaries like opencode.

## Usage

### Install

```bash
bash opencode-termux.sh install
```

### Uninstall

```bash
bash opencode-termux.sh uninstall
```

## Post-Installation

After installation, opencode will be placed in `~/.opencode/bin/`:

- `opencode` — wrapper script (launches via `grun`)
- `opencode.real` — original opencode binary

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENCODE_VERSION` | `latest` | opencode version to install (GitHub release tag) |

Example:

```bash
OPENCODE_VERSION="v0.5.0" bash opencode-termux.sh install
```

## Supported Architectures

- `aarch64` (arm64)

## License

MIT
