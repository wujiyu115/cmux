# WSL 新终端启动慢 / 卡死：排查与修复记录

日期：2026-09-10 ｜ 环境：Windows 10 19045 (x64)、WSL2 + Ubuntu 20.04、omp (oh-my-pi，`gy` 启动)

## 症状

在一个 TeamPilot WSL 终端里运行 `gy`（启动 omp）一段时间后，再新开一个 WSL 终端：

- **早期症状**：TeamPilot.exe 整个无响应（UI 线程冻结 20–60+ 秒），只能杀进程。
- **修复中症状**：UI 不再冻结，但新终端报 `[Failed to start CLI: spawn timed out]`。
- **最终症状**：新终端要等约 60 秒才出现 shell 提示符，之后一切正常。
- 对照：**不启动 gy 时，新开 WSL 终端 <100ms**。gy 是否运行是决定性变量。

## 结论（TL;DR）

60 秒耗时全部花在 Windows 原生 `CreatePseudoConsole`（ConPTY 的 conhost.exe 宿主创建）上。当已有 ConPTY 会话（omp 的 Node TUI）高频重绘输出时，Win10 console 子系统（condrv/conhost 全局同步）会让新建 console 阻塞排队，并精确等待 **60 秒**（Windows 内部超时值，两轮复现实测 60031ms / 60043ms）后成功返回。这是 OS 层行为，应用侧无法消除，只能（a）不阻塞 UI、（b）不误杀慢启动、（c）防止进程泄漏放大它。

应用侧共发现并修复了三层缺陷 + 一个泄漏隐患，全部有回归测试。

## 排查过程（按发现顺序）

| 层 | 缺陷 | 手段 | 修复 |
|----|------|------|------|
| 1 | UI 线程同步跑 `where.exe` PATH 探测（`connectWorkspaceShell` → `CliExecutableValidator.validateLaunch` → `Process.runSync`），WSL 饱和下 CreateProcess 阻塞 20–60s | post-frame 回调逐个加 `pfz-cb begin/end` 括号 + procdump minidump（主线程栈顶 `CreateProcessInternalW`） | 删除冗余同步校验（异步校验已存在于 launch controller）；同步校验器加 `usesWsl` 短路 |
| 2 | `Pty.start` 的 `pty_create` FFI 在 UI 线程同步执行，其中 ConPTY 创建阻塞 60s | FRZ trace 括号 `spawn pty` → `spawn pty-end`；pty 日志 `ptystart begin/end` | 新增 `Pty.startAsync`：`pty_create` 放进短命辅助 isolate（`Isolate.run`） |
| 3 | 单一 15s `startupDeadline` 覆盖了 spawn 阶段，把 21–69s 才成功返回的 spawn 判成失败（"spawn timed out"） | trace 显示两次 spawn 分别 60043ms/21771ms 且都成功，超时先到 | 拆分为 `spawnDeadline`（默认 3 分钟，覆盖 PTY 创建）+ transport 就绪后再布防 15s `startupDeadline` |
| 4 | 无 Job Object：应用被强杀/崩溃时 wsl.exe 子进程可能泄漏，累积的 ConPTY 会话会放大 console 争用 | 强杀应用实测（修复前遗留、修复后自动回收） | `pty_create` 内给子进程挂 kill-on-close Job Object |

## 根因证据（原生逐步计时）

在 `flutter_pty_win.c` 的 `pty_create` 内给每步加计时（`FRZ_NATIVE_TRACE=1` 环境变量开启，写入 `%TEMP%\teampilot_pty_native_<pid>.log`）：

| 步骤 | 无 gy（对照） | gy 运行中开新终端 |
|------|--------------|-------------------|
| `CreatePipe` ×2 | 0ms | 0ms |
| **`CreatePseudoConsole`** | **15ms** | **60,031ms** |
| `CreateProcessW`（启动 wsl.exe） | 31ms | 31ms |
| 合计 | 46–73ms | 60,062ms |

时间线（同一轮复现）：

```
12:41:20–24  第一个终端敲 gy 回车（ptyw 日志确认输入）
12:41:28.824 新终端 pty_create 开始
12:42:28.865 CreatePseudoConsole 返回（60,031ms）
12:42:28.996 新终端 shell 第一波输出（完成后仅 ~112ms 出提示符）
```

关键判别点：

- `CreateProcessW` 始终 31ms → **不是**进程创建饱和，而是 console 子系统争用（修正了排查中期的假设）。
- 两轮复现都是精确 ~60s → 排队等内部超时，非随机延迟。
- WSL 本身不慢：spawn 返回后 shell 96–112ms 出输出。
- UI 全程响应（watchdog 0 次主线程阻塞）→ 修复 2 生效。

## 修复明细

### `client/packages/flutter_pty_new/lib/flutter_pty_new.dart`

- `Pty.startAsync()`：把 `pty_create` FFI 放进 `Isolate.run` 短命 isolate。`Dart_Port` 是进程级 id，原生读/退出线程直接回投主 isolate 的 ReceivePort；退出监听在 spawn 前布防（快速退出的子进程在 spawn 完成前就发退出码，ReceivePort 无监听会丢消息）。
- 选项结构体（argv/envp/cwd）在辅助 isolate 内构建并在 FFI 返回后释放；原生侧在 `CreateProcessW` 前拷贝全部字符串，句柄地址以 int 传回主 isolate。
- `Pty.start`（同步版）保留，重构为共用 `_createPtyNative`，供测试与非 UI 场景使用。

### `client/lib/services/terminal/terminal_transport_starter.dart`、`terminal_transport_factory.dart`

两个生产调用点改用 `Pty.startAsync`。（`flutter_alacritty` 的 `FlutterPtyBackend` 是 example/test-only，未改。）

### `client/lib/services/terminal/terminal_launch_controller.dart` + `terminal_session.dart`

`beginStartup` 布防 `spawnDeadline`（默认 3 分钟）；`_enterConfirmingPhase`（transport 已存在）时重新布防原 15s `startupDeadline`。`TerminalSession` 新增 `spawnDeadline` 参数透传。

### `client/packages/flutter_pty_new/src/flutter_pty_win.c`

- `create_kill_on_close_job()`：每个 PTY 子进程挂 kill-on-close Job Object——应用正常退出/崩溃/被强杀时 OS 自动终止子进程。实测：强杀应用，其名下 wsl.exe 全部死亡。

### `client/lib/services/cli/cli_executable_validator.dart`

同步 `validateLaunch` 加 `usesWsl` 短路（与异步版一致）：WSL 调用跳过会同步 spawn `where.exe` 的 PATH 探测。

## 回归测试

- `flutter_pty_new/example/integration_test/flutter_pty_test.dart`：新增 4 个 `startAsync` 测试（正常 IO、快速退出子进程的退出码、workingDirectory、环境变量），13/13 通过。
- `client/test/services/terminal/terminal_session_test.dart`：
  - `spawn deadline` 组（fakeAsync）：慢 spawn 超过 15s 不误杀并最终 running；超过 `spawnDeadline` 报错且迟到的 transport 被关闭不复活会话。
  - 既有 "spawn timeout" 测试迁移到 `spawnDeadline` 参数。
  - `connectWorkspaceShell validation` 组：WSL plan 不触发同步 PATH 探测直达 transport。
- `client/test/services/cli/cli_executable_validator_test.dart`：WSL 短路 + 缺失绝对路径快速失败。

## 仍然存在的 60 秒（OS 层，应用侧无法消除）

`CreatePseudoConsole` 在 Win10 console 栈下的争用是 Windows 行为。缓解建议：

1. 减少并存 ConPTY 会话数（VS Code Remote-WSL 服务、Windows Terminal WSL 标签、TeamPilot 终端共用同一 console 子系统）。
2. 怀疑累积状态时跑 `wsl --shutdown` 重置 WSL VM（vmmem 内存也会释放）。
3. Windows 11 的新 conhost 有改进，有条件可对比。

应用侧保证的是：UI 不冻结（阻塞在后台 isolate）、3 分钟内成功的慢启动不被误杀、应用退出不泄漏子进程。

## 排查中的两个教训（供未来复用）

1. **PID 复用会制造"孤儿"假象**：按"父 PID 已死"判定孤儿 wsl.exe 时，五个死掉的父 PID 已被 VS Code/WindowsTerminal 复用，且那些 wsl.exe 实为 VS Code 合法子进程（命令行含 `wslServer.sh` / `.vscode-server`）。判定进程归属必须看**命令行**，不能只看父 PID。
2. **多轮"修一层、露一层"是同一根因的不同切面**：`where.exe` 同步探测、`pty_create` 同步 FFI、15s 超时误杀——三层的直接诱因都是同一个 60s 的 OS 停滞，但暴露在不同接缝。修复后逐层复现验证才能确认没有下一层。

## 诊断手段备忘（探针均为临时代码，已全部移除）

- FRZ trace（`--dart-define=FRZ_TRACE=1`）：主 isolate 逐语句括号 + post-frame 回调括号 + watchdog（pong 间隙 >1s 即主线程阻塞）。
- 原生计时（`FRZ_NATIVE_TRACE=1`）：`pty_create` 内 `CreatePipe` / `CreatePseudoConsole` / `CreateProcessW` / total 四步毫秒数。
- procdump `-h -n 1 <pid>` 抓冻结瞬间 minidump；主线程栈顶 `CreateProcessInternalW` 即 UI 线程在同步建进程。
