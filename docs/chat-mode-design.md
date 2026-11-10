# Chat mode / terminal mode

日期：2026-11 ｜ 参考实现：[stablyai/orca](https://github.com/stablyai/orca) `main`（MIT，仅静态阅读源码 + 官方文档，未运行）

本文记录两件事：**Orca 的聊天模式是怎么做的**，以及**TeamPilot 为什么只抄一半**、抄的是哪一半。

---

## 1. Orca 有两种 chat，不要混为一谈

读 `src/main/native-chat/`（675 个非测试文件）、`src/main/acp/`（168）、`mobile/src/session/native-chat/`，以及 `docs/site/content/docs/agents/native-chat.mdx` 后可以确认：orca 的 "Chat UI" 是两条完全不同的技术路线，UI 长得一样。

### 1.1 结构化 chat（structured / native chat）

不走终端。UI 是 agent 协议的**原生客户端**，每套 CLI 一个适配层：

| CLI | 通道 | 证据（orca 源码路径） |
|---|---|---|
| Claude | Agent SDK 控制协议（`control_request` / `can_use_tool` / 流式 message） | `src/main/claude/claude-agent-sdk-control-requests.ts`、`claude-child-tool-queries.ts` |
| Codex | `codex app-server` JSON-RPC（`session/new`、`turn/*`、通知流） | `src/main/codex/app-server/codex-app-server-*.ts` |
| Grok / opencode / Antigravity / omp | ACP（Agent Client Protocol）+ 各自 dialect | `src/main/acp/acp-dialects/{grok,opencode,omp,antigravity}-dialect.ts` |

官方文档原话：结构化 chat「communicates directly with the agent rather than displaying a terminal session」。代价是这类 tab **没有**就地切回终端的视图——要换形态只能 `Continue with Terminal Agent` 复制出另一个会话。另外每套 CLI 都要维护 model 目录、session option、slash command、permission 卡片、用量、审批……这就是 1900+ 文件的原因（`agent-model-catalog/` 一个目录就 30+ 文件）。

### 1.2 终端承载的 chat（terminal-backed chat）

终端里照常跑 agent CLI，chat 只是**同一进程的另一种呈现**：

- 官方文档：「A terminal-backed chat is a view over a running terminal agent, so switching it does not create a new session」；`Show terminal` / `Ctrl+Shift+J` 来回切；`Continue in Chat UI` 把已有终端会话「shows that same terminal session as a transcript」。
- 会话内容从**CLI 自己写的会话库**取（`~/.claude/projects/…/*.jsonl`、`~/.codex/sessions/…/rollout-*.jsonl`），不是抓 PTY 字节流——orca 有专门的 `config/scripts/diagnostics/terminal-transcripts/capture-agent-pty-transcript.mjs` 说明他们确实验证过 PTY 路线但没走它。
- 手机端：`mobile/src/session/native-chat/transcript/*` 一整套行渲染（`MobileNativeChatProse`、`…ToolPairing…`、`…ReasoningRow`、`…NoticeRow`），RPC golden 里直接有 `session-create-terminal-agent-launched-as-chat.json`、`matrix-session.native-chat-page-nativechat.*` —— 也就是**模式是 session 的线上属性**，手机据此决定画终端还是画对话。

### 1.3 和设置的关系

Orca 里 `Settings → Agents` 每个 agent 一行 `Chat | CLI`，决定**新会话**用哪种形态；已存在的会话保持原形态（「changing an agent's Chat or CLI choice does not convert existing sessions」）。你截图里那句「Chat UI 已开启 / 新智能体默认以聊天模式启动」就是这条。

TeamPilot 抄的是同一条语义，只是作用在 pane 上：`设置 → 会话 → 新窗口默认模式` + `聊天模式的启动命令`，新窗口/分屏按它创建，已开着的窗口不受影响（§3.1）。

---

## 2. TeamPilot 取哪一半：只取 1.2

理由很硬：

1. **本仓不编排 agent**。结构化 chat 要求 app 拥有 agent 进程的生命周期与协议，等于换一个产品（`docs/feature-comparison-orca.md` 的结论也是这句）。1.2 只读文件：app 不托管进程、不讲协议。唯一的例外是聊天窗口创建时把设置里的命令**敲进 pane 自己的 shell**（§3.1），进程仍然属于那个 shell。
2. **1.2 保留终端作为同一个 pane 的第二视图**（逃生口），而 1.1 换掉终端就没有了。
3. **WSL/Windows 零分叉**：1.2 只读文件，读写都走 `RuntimeContext.filesystem`——local 是 `LocalFilesystem`、WSL 是 `WslFilesystem`（每 op 一个 `wsl.exe` 进程）、SSH 是 `SftpFilesystem`。同一份代码三种机器，不需要为 distro 或盘符写分支。
4. **手机端只多一层渲染**：行模型可以序列化，桌面与手机画同一份 `ChatTranscriptSnapshot`。

> 代价：只支持「CLI 会把会话写进本地库」的 agent（claude / qoder / codex / opencode / omp 都有，本仓 `AgentCliSessionAdapter` 已在扫这些库），并且只读——不能像 1.1 那样在 chat 里做审批卡片、model 切换、rewind。这些留在终端里做。

---

## 3. 设计

### 3.1 模式是创建时的选项（历史：曾经是视图开关）

模式在 **pane 创建时**决定，之后不再改变（`PaneMode`）：

| 模式 | 是什么 | 创建时做什么 |
|---|---|---|
| `terminal` | 普通交互 shell | 什么也不敲 |
| `chat` | 同一条 PTY，但视图读 agent 自己写的会话库，渲染成对话 | PTY 起来后，把设置里的命令（`claude` / `pi` / …）敲进去 |

- 设置来源：`SessionPreferences.newPaneMode` + `SessionPreferences.chatAgentCommand`（设置 → 会话）。新窗口（工作区 shell 标签、新建终端、分屏）都按它创建。
- 唯一的「启动 agent」点：`WorkspaceTerminalSessionOps.startChatAgent` → `chatAgentLaunchLine`（纯函数，可单测）。就是往 shell 里写一行，没有协议、没有托管子进程；CLI 仍然可被 Ctrl+C、可被用户在终端里接管。
- 逃生口：聊天 pane 的工具条保留一个按钮，只切换**视图**（看终端 / 回到对话），不动模式也不动 agent。终端 pane 没有这个按钮。
- 不落盘：`notification`/`working directory` 那套 pane 事实本来就不持久化，模式跟着 pane 的生命周期走；重开工作区就是新建 pane，重新按设置来。
- `ChatTranscriptRegistry` 现在只放**读会话的读者**（`paneId → ChatTranscriptSession`），不再回答「什么模式」。模式在 `WorkspaceTerminalEntry.mode`，配对协议 `session.list` / `chat.read` 的 `mode` 都从它来。
- 历史：早期版本是「一个 pane 两个视图 + 工具条按钮切换」，手机端靠 1 秒轮询问「现在是什么模式」。那样既要在运行时猜归属，又让模式变成随时会变的东西；改成创建时定模式后，两件事一起消失。

### 3.2 会话文件怎么定位

`ChatTranscriptSession`（`lib/services/chat/chat_transcript_session.dart`）：

1. 用 pane 的 cwd（OSC 7 优先，WSL 走 `windowsPathToWsl` 还原成 `/home/...`；见 `_directoryForEntry`）+ 该 pane 的 `RuntimeTarget`。
2. 交给已有的 `AgentCliSessionService`（就是「恢复会话」菜单用的那个）扫该机器上 5 个 CLI 的会话库，按下面的规则挑一条。
3. adapter 顺带返回 `filePath`（本次新增字段），所以拿到记录就能直接读文件，不用按家目录规则反推路径。

挑哪一条，两级：

| 级别 | 条件 | 说明 |
|---|---|---|
| own | `createdAt >= paneStart - 2min` | pane 自己的 PTY 启动的会话。`createdAt` 来自会话库本身：pi 家族在文件名里（`2026-11-09T13-14-26-493Z_<id>.jsonl`），Claude 系在第一条记录的 `timestamp` 上。 |
| borrowed | 只剩 `updatedAt >= paneStart`（不带 2 分钟宽容） | `--resume` 恢复的会话保留原始创建时间，只能靠「恢复时会写启动记录」的 mtime 认领；别的窗口里已经在跑的会话在 pane 启动之前就动过了，认领不了。 |

**为什么不能只看 mtime**：另一个窗口里的会话只要还在跑，mtime 就一直更新，于是「最新的那条」永远指向别人。曾经因此出现过「聊天视图显示了内容，但发消息毫无反应」——视图读的是另一个窗口的会话，消息写进了自己 pane 的 agent，两边对不上。

**发送即校准**（`markPromptSent`）：发送后 20 秒内，如果当前文件里没出现这条 prompt，就去扫同目录最近 3 分钟内改动过的其它会话文件，谁的**最后一条 user 记录**等于这条 prompt，谁就是这个 pane 的真身，直接重绑并在同一次轮询里渲染出来。CLI 一收到输入就落盘，所以这是最可靠的判据——猜测只能在第一条消息之后自我纠正。

**送不到就说话**：发送后 5 秒内会话文件没有出现这条 prompt，输入框上方显示错误、文本还回输入框（`chatPanePromptUndelivered`）。会话库是唯一证据，静默吞掉是最差的结果。

自动重绑只覆盖桌面端面板：手机端的输入走终端字节流，宿主分不清「聊天模式里打的一句话」和「终端里敲的键」，所以手机上发送不会触发校准（读到的内容会随桌面端的校准一起对）。

### 3.3 命令跑在 pane 自己的 shell 里

`chatAgentCommand` 是被敲进**这条 PTY 的 shell**，不是托管子进程，所以它必须是一条那个 shell 认得的命令：

- Windows 本地 pane 的 shell 是 `cmd.exe`：`claude` 是 `.exe`，能用；`pi`（`~/.bun/bin/pi` 是 bash 脚本）不行，
  要写成 `bash -lc pi` 或该 CLI 的绝对路径。
- WSL / SSH pane 是 POSIX shell：`pi` / `claude` 按各自 PATH 解析。

失败不会静默：agent 什么都没写出来时，聊天视图显示「智能体已启动，等它写下第一句话…」，输入框照常可用（prompt 会进到 shell 里），
点工具条的终端图标就能看到 shell 的真实报错。

### 3.4 为什么是轮询而不是 watch

WSL 后端的每个文件操作都是一次 `wsl.exe` 进程（`docs/wsl-fs-helper-design.md` 的老问题）。`FsWatcher` 只有本地/部分后端支持，WSL 上事件驱动反而更贵。所以：固定 800ms 轮询 `stat`，size/mtime 没变就什么都不做；变了才整文件重读 + 重解析。

整文件重读而非增量追加，是因为 CLI 会**改写**前面的记录（title、cost、流式 assistant 块），追加式解析会漂。实际会话文件几百 KB，重解析只要几毫秒。

### 3.5 行模型

`ChatTranscriptRow{ id, kind, text, toolName, detail, running, at }`，`kind ∈ {user, assistant, thought, tool, notice}`。

- `id` 稳定（`<messageId>#<块序号>`），重新解析时同 id 原地替换，界面不会因为一次轮询就重建整个列表。
- 工具行 = 名字 + 一行目标（`Bash  flutter test`），输出折叠；`running` 表示还没等到 `tool_result`。
- `thinking` 块折叠成「思考」；`isSidechain`（子 agent 的对话）、`attachment`、`hook` 摘要、`cost-state` 等噪声一律跳过。
- 工具输出截到 4000 字符：它要发给手机，不能让一次 `cat` 把整条链路撑爆。

### 3.6 解析器现状

`chatTranscriptParserFor(family)`：

| family | 状态 |
|---|---|
| claude / qoder（同一 JSONL schema） | ✅ `ClaudeStyleChatTranscriptParser` |
| pi / oh-my-pi（同一 JSONL schema，`message` 记录） | ✅ `PiChatTranscriptParser` |
| codex | ⏳ 待做（`event_msg` / `response_item`） |
| opencode | ⏳ 待做（storage 是多个小 json，不是单文件 jsonl） |

pi 家族两个 store 的差别只在目录规则（记录格式完全相同，omp 是 pi 的 fork）：

| CLI | 目录 | 规则 |
|---|---|---|
| pi | `~/.pi/agent/sessions/<safePath>/<ISO>_<sessionId>.jsonl` | `--` + `cwd` 去掉开头分隔符、`/ \ :` 全换成 `-` + `--`（`D:\git\x` → `--D--git-x--`） |
| omp | `~/.omp/agent/sessions/<munged>/…` | 先剥 `$HOME` 前缀再 `mungeDirectory`（`/home/u/git/x` → `-git-x`） |

pi 的 `message` 行按 `role` 分四类：`user`（content 是 `text` block 列表）、`assistant`（`text` / `thinking` / `toolCall`）、`toolResult`（用 `toolCallId` 把输出接回对应的 `toolCall` 行）、`system`（跳过）。`compaction` 行渲染成和 Claude `compact_boundary` 一样的 notice。

没有解析器的 family → 面板显示「这个格式还读不了，请用终端」，不是空白。

---

## 4. 交互

- 面板工具栏多一个按钮（`Icons.forum_outlined` ↔ `Icons.terminal`），切换**当前 pane**。切走时 split tree 原样留着，切回来立刻恢复。
- chat 视图：行列表 + 底部输入框。输入框把文本写进**同一个 PTY**（`session.input.writeToPty('$text\r')`），并调 `markUserTurnStarted()`，所以空闲通知、命令日志等既有机制照旧。
- 滚动只在「本来就在底部」时跟随新行，往回翻不会被下一次轮询打断。
- 手机端：`session.list` 的每条带 `mode`（来源是 `WorkspaceTerminalEntry.mode`，不是「有没有会话内容」）；镜面页每秒 `chat.read` 一次，拿内容和 `mode`，chat 模式复用同一个 `ChatTranscriptPane`，输入框写进同一个 PTY。模式不会在镜像期间变（pane 建好就定了），所以这一秒一次的往返只是刷内容，不是在猜模式。

---

## 5. 本次落地与待办

已实现（`client/`）：

- `services/chat/chat_transcript_row.dart` — 行模型 + 线上 JSON
- `services/chat/chat_transcript_parser.dart` — claude/qoder JSONL → 行
- `services/chat/chat_transcript_session.dart` — 定位 + 轮询 + 解析 + `busy`
- `services/chat/chat_transcript_registry.dart` — pane 模式
- `pages/home_workspace/workspace/chat/chat_transcript_pane.dart` — 对话视图 + 输入框
- `PaneMode` + 设置项（`newPaneMode` / `chatAgentCommand`）+ `WorkspaceTerminalSessionOps.startChatAgent`；`AgentCliSessionRecord.filePath`
- 配对协议：`session.list` 带 `mode`、`chat.read` 返回 `{mode, transcript}`；镜面页按模式二选一
- 测试：parser 9 例、session 7 例、pane 6 例、rpc 4 例

### 手机端验证（MuMu 平板模拟器，真机级）

用 `tool/pair_host_probe.dart` 编译成 release 宿主（`flutter build windows --release -t tool/pair_host_probe.dart`），
`TP_PROBE_ADDR=127.0.0.1` + `adb reverse tcp:47821 tcp:47821`，平板模拟器配对后：

- `probe-chat` 在手机上渲染为对话（用户气泡 / 折叠「思考」/ 助手正文 / 折叠工具行 / 输入框），**没有**终端工具条；
- `probe-alpha` 同时仍是终端 + 工具条 —— 模式逐 pane 生效，不是全局开关；
- 手机输入「hello demo from mumu」→ 宿主把这一轮写进 JSONL → 手机轮询后出现该气泡与回复（同一条 PTY，agent 没被打断）；
- 同一宿主同时有 chat pane 与 terminal pane → 手机按 pane 分别渲染，互不影响（模式来自 `session.list`，不是「有没有内容」）；
- 平板尺寸（最短边 800dp）下左侧列表 + 右侧视图，选中行高亮；手机尺寸（411×914dp）下是单栏 push。

过程中修掉两个真问题（都不是本次功能引入的）：

1. **冷启动深链路由崩**：Android 把 VIEW intent 的 URI 当作 `defaultRouteName`，GoRouter 用它覆盖了 `initialLocation`，
   `teampilot://pair?…` 落到「Page Not Found」。现在 `pairingDeepLinkDestination` 把 scheme 为 `teampilot` 的位置改道 `/home-v2`，
   深链仍由 shell（`app_links`）处理。
2. **重复切到 chat 会丢历史**：构造 `ChatTranscriptSession` 时用的是 `DateTime.now()`，切第二次就超出「文件写在 pane 之后」的窗口，
   显示「没有会话记录」。改为锚定 pane 的 PTY 启动时间（`WorkspaceTerminalEntry.startedAt`）。
3. 轮询失败不再永久停摆：只有宿主**明确回答** `unknown method`（旧桌面）才停；超时/断线继续重试，
   否则一次掉线之后手机永远停在旧模式。

待办：

1. codex / opencode 解析器（pi 与 oh-my-pi 已完成）
3. `busy` 期间输入框的「停止」按钮（现在只能靠终端里 Ctrl+C）
4. 未做：审批卡片、model/slash command 面板——按 §2 的取舍留在终端