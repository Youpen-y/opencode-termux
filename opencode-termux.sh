#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# opencode Termux 安装方案
# 
# 原理：
#   opencode 是为 Linux glibc 编译的 Go 二进制，无法在 Termux (Bionic libc)
#   上直接运行。本方案利用 Termux 官方的 glibc 子系统来提供运行环境。
#
#   关键组件：
#     glibc-repo    — Termux 的 glibc 软件源
#     glibc-runner  — 提供 grun 命令，用于在 Termux 中启动 glibc 二进制
#
#   grun 的工作方式：
#     1. unset LD_PRELOAD（避免 Termux 的 termux-exec 与 glibc 冲突）
#     2. 通过 glibc 的 ld.so 启动目标二进制
#     3. 自动设置正确的库搜索路径
#
#   注意：不要使用 grun --configure，它会用 patchelf 修改二进制，
#         对 opencode 这种 Go 二进制会导致 segfault。
#
# 用法：
#   bash opencode-termux.sh install    # 安装 opencode
#   bash opencode-termux.sh upgrade    # 升级 opencode（保留 wrapper）
#   bash opencode-termux.sh uninstall  # 卸载 opencode
# ============================================================

set -euo pipefail

OPENCODE_DIR="$HOME/.opencode/bin"
OPENCODE_VERSION="${OPENCODE_VERSION:-latest}"
ARCH=$(uname -m)

case "$ARCH" in
    aarch64) BINARY_ARCH="arm64" ;;
    *)       echo "不支持的架构: $ARCH (仅支持 aarch64)"; exit 1 ;;
esac

info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m $*"; }
die()   { echo -e "\033[1;31m[ERROR]\033[0m $*"; exit 1; }

# --------------------------------------------------
ensure_glibc() {
    local glibc_lib="${PREFIX:-/data/data/com.termux/files/usr}/glibc/lib"

    if [ -f "$glibc_lib/ld-linux-aarch64.so.1" ] && command -v grun >/dev/null 2>&1; then
        ok "glibc 子系统已就绪"
        return
    fi

    info "安装 glibc 子系统..."
    pkg install -y glibc-repo   || die "安装 glibc-repo 失败"
    pkg install -y glibc-runner || die "安装 glibc-runner 失败"

    command -v grun >/dev/null || die "grun 未找到"
    ok "glibc 子系统安装完成"
}

# --------------------------------------------------
# 下载 opencode（返回 download_url 到 stdout，供调用方使用）
# --------------------------------------------------
fetch_download_url() {
    local repo="anomalyco/opencode"
    local release_url="https://api.github.com/repos/${repo}/releases/${OPENCODE_VERSION}"

    local url
    url=$(curl -sL "$release_url" | \
        grep -o '"browser_download_url": *"[^"]*"' | \
        grep "linux-${BINARY_ARCH}.tar.gz" | \
        grep -v musl | \
        head -1 | sed 's/.*"browser_download_url": *"//;s/"$//')

    [ -z "$url" ] && die "未找到 linux-${BINARY_ARCH} (glibc) 版本"
    echo "$url"
}

# --------------------------------------------------
# 下载并解压 opencode 到指定目录
# 参数: $1 = 目标目录（二进制会放在 $1/opencode）
# --------------------------------------------------
download_to() {
    local target_dir="$1"
    local download_url ver
    download_url=$(fetch_download_url)
    ver=$(basename "$(dirname "$download_url")")
    info "下载 opencode ${ver} (linux-${BINARY_ARCH}, glibc)..."

    local tmpdir="${TMPDIR:-$HOME/.tmp}"
    mkdir -p "$tmpdir"
    curl -L --progress-bar -o "$tmpdir/opencode.tar.gz" "$download_url"
    mkdir -p "$target_dir"
    tar xzf "$tmpdir/opencode.tar.gz" -C "$target_dir"
    chmod +x "$target_dir/opencode"
    rm -f "$tmpdir/opencode.tar.gz"
    ok "下载完成: $ver"
}

# --------------------------------------------------
# 安装
# --------------------------------------------------
install_opencode() {
    echo "=========================================="
    echo "  opencode Termux 安装方案"
    echo "=========================================="
    ensure_glibc

    if [ -f "$OPENCODE_DIR/opencode.real" ]; then
        # 已有安装 → 只替换二进制，保留 wrapper
        local tmpdir="${TMPDIR:-$HOME/.tmp}"
        download_to "$tmpdir"
        mv -f "$tmpdir/opencode" "$OPENCODE_DIR/opencode.real"
        chmod +x "$OPENCODE_DIR/opencode.real"
        rm -rf "$tmpdir/opencode.tar.gz" "$tmpdir/opencode"
        ok "已更新 opencode.real"
    else
        download_to "$OPENCODE_DIR"
        create_wrapper
    fi

    verify
}

# --------------------------------------------------
# 创建 wrapper（将 opencode 重命名为 opencode.real）
# --------------------------------------------------
create_wrapper() {
    [ -f "$OPENCODE_DIR/opencode" ] || die "$OPENCODE_DIR/opencode 不存在"

    if [ -f "$OPENCODE_DIR/opencode.real" ]; then
        # 已有 wrapper 和旧二进制 → 只替换二进制
        mv "$OPENCODE_DIR/opencode" "$OPENCODE_DIR/opencode.real"
        ok "已更新 opencode.real"
        return
    fi

    mv "$OPENCODE_DIR/opencode" "$OPENCODE_DIR/opencode.real"

    cat > "$OPENCODE_DIR/opencode" << 'WRAPPER'
#!/data/data/com.termux/files/usr/bin/bash
exec grun "$HOME/.opencode/bin/opencode.real" "$@"
WRAPPER
    chmod +x "$OPENCODE_DIR/opencode"
    ok "启动脚本已创建"
}

# --------------------------------------------------
# 升级（只替换 opencode.real，保留 wrapper）
# --------------------------------------------------
upgrade_opencode() {
    [ -f "$OPENCODE_DIR/opencode.real" ] || die "未找到 opencode.real，请先运行 install"

    local old_ver new_ver
    old_ver=$(grun "$OPENCODE_DIR/opencode.real" --version 2>/dev/null || echo unknown)

    OPENCODE_VERSION=latest
    info "检查最新版本..."

    local download_url
    download_url=$(fetch_download_url)
    new_ver=$(basename "$(dirname "$download_url")")

    if [ "$old_ver" = "$new_ver" ]; then
        ok "已是最新版本 ($old_ver)"
        return
    fi

    info "升级: $old_ver → $new_ver"

    local tmpdir="${TMPDIR:-$HOME/.tmp}"
    mkdir -p "$tmpdir"
    curl -L --progress-bar -o "$tmpdir/opencode.tar.gz" "$download_url"

    # 备份旧版本
    mv "$OPENCODE_DIR/opencode.real" "$OPENCODE_DIR/opencode.real.bak"

    # 解压新二进制
    tar xzf "$tmpdir/opencode.tar.gz" -C "$tmpdir"
    mv "$tmpdir/opencode" "$OPENCODE_DIR/opencode.real"
    chmod +x "$OPENCODE_DIR/opencode.real"
    rm -rf "$tmpdir/opencode.tar.gz" "$tmpdir/opencode"

    # 验证新版本
    if ! grun "$OPENCODE_DIR/opencode.real" --version >/dev/null 2>&1; then
        echo -e "\033[1;31m[ERROR]\033[0m 新版本验证失败，回滚..."
        mv "$OPENCODE_DIR/opencode.real.bak" "$OPENCODE_DIR/opencode.real"
        die "已回滚到 $old_ver"
    fi

    rm -f "$OPENCODE_DIR/opencode.real.bak"
    ok "升级完成: $old_ver → $new_ver"
}

# --------------------------------------------------
verify() {
    info "验证安装..."
    local v
    v=$(opencode --version 2>&1) || true
    if echo "$v" | grep -qE '^[0-9]+\.'; then
        ok "opencode $v 安装成功！"
        echo ""
        echo "  启动：opencode"
        echo "  帮助：opencode --help"
        echo "  升级：bash opencode-termux.sh upgrade"
    else
        die "验证失败: $v"
    fi
}

# --------------------------------------------------
uninstall() {
    rm -rf "$HOME/.opencode"
    ok "已卸载 opencode"
    echo "如需同时移除 glibc 子系统：pkg uninstall glibc-runner glibc-repo"
}

# --------------------------------------------------
case "${1:-}" in
    install)
        install_opencode
        ;;
    upgrade)
        ensure_glibc
        upgrade_opencode
        ;;
    uninstall)
        uninstall
        ;;
    *)
        echo "用法: bash opencode-termux.sh {install|upgrade|uninstall}"
        ;;
esac
