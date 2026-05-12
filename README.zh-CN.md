# opencode-termux

在 Termux 环境下安装和运行 [opencode](https://github.com/anomalyco/opencode) 的脚本方案。

## 原理

opencode 是为 Linux glibc 编译的 Go 二进制，无法在 Termux (Bionic libc) 上直接运行。本方案利用 Termux 官方的 glibc 子系统来提供运行环境。

### 关键组件

| 组件 | 说明 |
|------|------|
| `glibc-repo` | Termux 的 glibc 软件源 |
| `glibc-runner` | 提供 `grun` 命令，用于在 Termux 中启动 glibc 二进制 |

### `grun` 的工作方式

1. `unset LD_PRELOAD`（避免 Termux 的 `termux-exec` 与 glibc 冲突）
2. 通过 glibc 的 `ld.so` 启动目标二进制
3. 自动设置正确的库搜索路径

> **注意**：不要使用 `grun --configure`，它会用 `patchelf` 修改二进制，对 opencode 这种 Go 二进制会导致 segfault。

## 使用方法

### 安装

```bash
bash opencode-termux.sh install
```

### 卸载

```bash
bash opencode-termux.sh uninstall
```

## 安装后

安装完成后，opencode 会被放置在 `~/.opencode/bin/` 目录下：

- `opencode` — 包装脚本（通过 `grun` 启动）
- `opencode.real` — 原始 opencode 二进制

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `OPENCODE_VERSION` | `latest` | 要安装的 opencode 版本（GitHub release tag） |

示例：

```bash
OPENCODE_VERSION="v0.5.0" bash opencode-termux.sh install
```

## 支持的架构

- `aarch64` (arm64)

## 许可证

MIT
