#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# opencode Termux Installer
# 
# How it works:
#   opencode is a Go binary compiled against Linux glibc, which cannot
#   run directly on Termux (Bionic libc). This script leverages the
#   official Termux glibc subsystem to provide a compatible runtime.
#
#   Key components:
#     glibc-repo    — Termux's glibc package repository
#     glibc-runner  — Provides the `grun` command to launch glibc binaries
#
#   How grun works:
#     1. unsets LD_PRELOAD (avoids conflicts between termux-exec and glibc)
#     2. Launches the target binary via glibc's ld.so
#     3. Automatically sets the correct library search paths
#
#   NOTE: Do NOT use `grun --configure` — it uses patchelf to modify
#         the binary, which causes segfaults with Go binaries like opencode.
#
# Usage:
#   bash opencode-termux.sh install    # Install opencode
#   bash opencode-termux.sh uninstall  # Uninstall opencode
# ============================================================

set -euo pipefail

OPENCODE_DIR="$HOME/.opencode/bin"
OPENCODE_VERSION="${OPENCODE_VERSION:-latest}"
ARCH=$(uname -m)

case "$ARCH" in
    aarch64) BINARY_ARCH="arm64" ;;
    *)       echo "Unsupported architecture: $ARCH (only aarch64 is supported)"; exit 1 ;;
esac

info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m $*"; }
die()   { echo -e "\033[1;31m[ERROR]\033[0m $*"; exit 1; }

# --------------------------------------------------
ensure_glibc() {
    local glibc_lib="${PREFIX:-/data/data/com.termux/files/usr}/glibc/lib"

    if [ -f "$glibc_lib/ld-linux-aarch64.so.1" ] && command -v grun >/dev/null 2>&1; then
        ok "glibc subsystem is ready"
        return
    fi

    info "Installing glibc subsystem..."
    pkg install -y glibc-repo   || die "Failed to install glibc-repo"
    pkg install -y glibc-runner || die "Failed to install glibc-runner"

    command -v grun >/dev/null || die "grun not found"
    ok "glibc subsystem installed"
}

# --------------------------------------------------
download_opencode() {
    local repo="anomalyco/opencode"
    local release_url="https://api.github.com/repos/${repo}/releases/${OPENCODE_VERSION}"

    info "Fetching opencode release info..."
    local download_url
    download_url=$(curl -sL "$release_url" | \
        grep -o '"browser_download_url": *"[^"]*"' | \
        grep "linux-${BINARY_ARCH}.tar.gz" | \
        grep -v musl | \
        head -1 | sed 's/.*"browser_download_url": *"//;s/"$//')

    [ -z "$download_url" ] && die "linux-${BINARY_ARCH} (glibc) build not found"

    local ver
    ver=$(basename "$(dirname "$download_url")")
    info "Downloading opencode ${ver} (linux-${BINARY_ARCH}, glibc)..."

    mkdir -p "$OPENCODE_DIR"
    local tmpdir="${TMPDIR:-$HOME/.tmp}"
    mkdir -p "$tmpdir"
    curl -L --progress-bar -o "$tmpdir/opencode.tar.gz" "$download_url"
    tar xzf "$tmpdir/opencode.tar.gz" -C "$OPENCODE_DIR"
    chmod +x "$OPENCODE_DIR/opencode"
    rm -f "$tmpdir/opencode.tar.gz"

    ok "Download complete"
}

# --------------------------------------------------
create_wrapper() {
    # Rename the original binary to opencode.real
    mv "$OPENCODE_DIR/opencode" "$OPENCODE_DIR/opencode.real"

    cat > "$OPENCODE_DIR/opencode" << 'WRAPPER'
#!/data/data/com.termux/files/usr/bin/bash
exec grun "$HOME/.opencode/bin/opencode.real" "$@"
WRAPPER
    chmod +x "$OPENCODE_DIR/opencode"

    ok "Wrapper script created"
}

# --------------------------------------------------
verify() {
    info "Verifying installation..."
    local v
    v=$(opencode --version 2>&1) || true
    if echo "$v" | grep -qE '^[0-9]+\.'; then
        ok "opencode $v installed successfully!"
        echo ""
        echo "  Launch:  opencode"
        echo "  Help:    opencode --help"
    else
        die "Verification failed: $v"
    fi
}

# --------------------------------------------------
uninstall() {
    rm -rf "$HOME/.opencode"
    ok "opencode has been uninstalled"
    echo "To also remove the glibc subsystem: pkg uninstall glibc-runner glibc-repo"
}

# --------------------------------------------------
case "${1:-}" in
    install)
        echo "=========================================="
        echo "  opencode Termux Installer"
        echo "=========================================="
        ensure_glibc
        download_opencode
        create_wrapper
        verify
        ;;
    uninstall)
        uninstall
        ;;
    *)
        echo "Usage: bash opencode-termux.sh {install|uninstall}"
        ;;
esac
