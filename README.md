# TeamPilot

[开发指南](docs/DEVELOPMENT.md) · 架构与 AI 约定见 [AGENTS.md](AGENTS.md)

**TeamPilot** 是一个面向开发者的桌面客户端：以**工作区**为中心，把仓库目录、内嵌**终端会话**和一个轻量**内置 IDE**（文件树、编辑器、Git、worktree）整合到同一个窗口里。会话标签是**普通的交互式终端**——桌面端直接以本机 PTY 打开，或通过 **SSH** 连接远端主机（Android 端始终走 SSH）。你可以在终端里运行任何命令行工具，包括各类 AI Agent CLI（Claude Code、Codex、opencode、cursor、flashskyai 等）。

TeamPilot 不会替你启动或编排这些 CLI；它只负责把它们跑起来的**工作区、终端与 IDE 环境**组织好。此外还内置了针对 **Claude** 的**Agent 状态通知**：当 Agent 结束一轮或需要授权时弹出系统通知。

![应用预览](assets/image.png)
![应用预览](assets/image1.png)

## 核心能力

| 能力 | 说明 |
|------|------|
| **工作区** | 把一个或多个仓库目录组织为工作区；侧栏管理、分组、搜索，多个工作区以标签页并排打开。 |
| **终端会话** | 每个工作区可开多个终端标签，均为普通交互式 shell（本机 PTY 或 SSH），绑定到工作区目录。 |
| **内置 IDE** | 文件树、多标签代码编辑器、VS Code 风格的 Git 源代码管理、git worktree，与终端共享同一工作目录。 |
| **Agent 状态通知** | 通过 Claude Code 的 hook 上报运行状态，Agent 结束一轮或需要授权时发系统通知。 |
| **多机运行** | 每个工作区可运行在 **本机**、**WSL** 发行版或某个 **SSH** 主机上。 |

## 工作区与内置 IDE

同一个窗口里就能完成常见的仓库浏览、改文件、看 diff、提交 Git，并与内嵌终端并排使用。工作区侧栏按 **worktree** 分组会话；右侧工具栏提供文件树、源代码管理等面板，减少在 IDE 与终端之间来回切换。

### Git Worktree

在绑定 Git 仓库的工作区里，TeamPilot 原生支持 **git worktree** 工作流（桌面本机 / WSL；SSH / Android 端不提供创建与删除）：

| 能力 | 说明 |
|------|------|
| **按分支分组** | 侧栏会话按 worktree 折叠分组；选中某一分支即切换当前工作目录，文件树与 Git 面板随之跟随。 |
| **创建 worktree** | 从主仓库派生新分支或检出已有分支；目录默认落在应用数据下的 `worktrees/<仓库名>/<分支>`，也可在对话框中调整路径。 |
| **删除 worktree** | 支持强制删除（有未提交改动时）、可选同时删除分支、可选一并删除该 worktree 下的会话。 |
| **一键开会话** | 创建时可勾选「创建后在此开始一个会话」，在新 worktree 里直接打开终端。 |

适合并行开发多个功能分支、或在不影响主工作区的前提下让不同会话各自占用独立检出目录。

### 内置 IDE 能力

右侧工具栏与编辑区提供常见 IDE 能力，与终端共享同一工作目录，磁盘变更会联动刷新文件树与 Git 状态（本机 / WSL 实时监听；SSH 端按时机轮询刷新）：

| 模块 | 能力 |
|------|------|
| **文件树** | 浏览工作区目录；支持多根文件夹（VS Code 式折叠头）、过滤、新建文件/文件夹、复制/剪切/粘贴、重命名、删除、复制路径、用系统应用打开、**定位当前编辑文件**。 |
| **代码编辑器** | 基于 **re-editor** 的多标签内嵌编辑器；从文件树或 Git diff 打开文件，未保存改动有脏标记，关闭前提示保存。 |
| **源代码管理（Git）** | VS Code 风格的变更列表：暂存 / 取消暂存、按文件或目录暂存、放弃更改、分支切换、内联 **diff 视图**（语法高亮与行间导航）、填写提交说明并 **提交**。 |
| **工作区搜索** | 侧栏搜索入口：同时检索会话标题与仓库内文件内容，快速跳转到对应会话或文件。 |

## Agent 状态通知

TeamPilot 会安装一个 Claude Code hook，把 Agent 的生命周期事件上报到应用内的本机回环网关；应用据此匹配到对应会话，并在 Agent 结束一轮或需要授权时弹出系统通知——即使窗口在后台，也能及时知道该回到哪个会话。

## 安装

在 [GitHub Releases](https://github.com/hhoao/teampilot/releases) 打开最新版本，按系统下载对应文件（文件名形如 `teampilot-<版本>-…`）。

### Linux

**Debian / Ubuntu（`.deb`，推荐）**

```bash
sudo dpkg -i teampilot-*-linux.deb
# 若提示依赖缺失：
sudo apt install -f
```

安装后从应用菜单启动 **TeamPilot**。卸载：`sudo apt remove teampilot`（包名以 deb 元数据为准）。

**AppImage（免安装）**

```bash
chmod +x teampilot-*-linux.AppImage
./teampilot-*-linux.AppImage
```

需要 `libfuse2`（Ubuntu 22.04+ 常需 `sudo apt install libfuse2`）。若希望写入开始菜单 / Dock，可配合 [AppImageLauncher](https://github.com/TheAssassin/AppImageLauncher)。

桌面端默认在本机以 PTY 直接打开终端会话；也可在设置中改用 **SSH** 连接远端主机（终端在远端运行）。

### macOS

1. 下载 `teampilot-*-macos.dmg`。
2. 打开 DMG，将 **TeamPilot** 拖入「应用程序」。
3. 首次启动若被 Gatekeeper 拦截：「系统设置 → 隐私与安全性」中允许，或右键应用 →「打开」。

### Windows

任选一种安装包（同一 Release 中通常都有）：

| 文件 | 说明 |
|------|------|
| `*-windows-setup.exe` | **推荐**：Inno Setup 安装向导，自动创建快捷方式 |
| `*.msix` | 适用于已启用旁加载 / 企业分发的环境 |
| `*.zip` | 便携包：解压后运行其中的 `TeamPilot.exe`，不写注册表 |

若工具安装在 **WSL** 内，可在设置中将应用数据或工作目录指向 WSL；亦可在设置中配置 **SSH** 连接远端 Linux 开发机。

### Android

Android 版**不运行本机 PTY**，需通过 **SSH** 连接一台 Linux/macOS/Windows（WSL）主机。

1. 根据 CPU 架构下载 `teampilot-*-arm64-v8a.apk`（多数新机型）或 `teampilot-*-armeabi-v7a.apk`。
2. 允许「未知来源」后安装 APK。
3. 打开应用，在 **设置** 中配置 SSH 主机、用户与密钥（或密码）。

## 终端

内嵌终端使用 **[flutter_alacritty](https://github.com/hhoao/flutter_alacritty)** — 一个基于 Alacritty 的 Rust 引擎驱动的 Flutter 组件。桌面端通过 `flutter_pty_new` 打开本机 PTY，SSH 会话通过 `dartssh2` 连接远端。

## 从源码构建

安装包由 CI 自动构建；从源码编译见 **[开发指南](docs/DEVELOPMENT.md)**。

## 更多文档

| 文档 | 读者 | 内容 |
|------|------|------|
| [开发指南](docs/DEVELOPMENT.md) | 贡献者 / 维护者 | 环境、本地运行、测试、打包与 CI |
| [AGENTS.md](AGENTS.md) | 贡献者 / AI | 仓库结构、架构约定 |
| [工作区存储布局](docs/workspace-storage-layout.md) | 贡献者 / AI | `<teampilotRoot>` 下的磁盘路径 |

## 致谢

- 文件图标：[Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme)（MIT 协议），作者 Philipp Kief / material-extensions。

## 许可证

本项目采用 [GNU Affero General Public License v3.0](LICENSE)。

## 社区

| 渠道 | 链接 |
|------|------|
| **QQ 群** | `1016450915` |
| **Discord** | [加入频道](https://discord.com/channels/1518523215767666719/1518523216912449669) |

欢迎反馈问题、交流用法与贡献想法。
</content>
