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

`Settings → Agents` 每个 agent 一行 `Chat | CLI`，决定**新会话**用哪种形态；已存在的会话保持原形态（「changing an agent's Chat or CLI choice does not convert existing sessions」）。你截图里那句「Chat UI 已开启 / 新智能体默认以聊天模式启动」就是这条。

---

## 2. TeamPilot 取哪一半：只取 1.2

理由很硬：

1. **本仓不编排 agent**。`AGENTS.md`：app 开的是普通交互 shell，CLI 由用户自己敲。结构化 chat 要求 app 拥有 agent 进程的生命周期与协议，等于换一个产品（`docs/feature-comparison-orca.md` 的结论也是这句）。
2. **1.2 天然满足「终端 ↔ 聊天就地切换」**，而 1.1 就地切不了。
3. **WSL/Windows 零分叉**：1.2 只读文件，读写都走 `RuntimeContext.filesystem`——local 是 `LocalFilesystem`、WSL 是 `WslFilesystem`（每 op 一个 `wsl.exe` 进程）、SSH 是 `SftpFilesystem`。同一份代码三种机器，不需要为 distro 或盘符写分支。
4. **手机端只多一层渲染**：行模型可以序列化，桌面与手机画同一份 `ChatTranscriptSnapshot`。

> 代价：只支持「CLI 会把会话写进本地库」的 agent（claude / qoder / codex / opencode / omp 都有，本仓 `AgentCliSessionAdapter` 已在扫这些库），并且只读——不能像 1.1 那样在 chat 里做审批卡片、model 切换、rewind。这些留在终端里做。

---

## 3. 设计

### 3.1 模式挂在「活着的 pane」上

`ChatTranscriptRegistry`（`lib/services/chat/chat_transcript_registry.dart`）记录 `paneId → ChatTranscriptSession`：

- 在 registry 里 = 这个 pane 正在画 chat；不在 = 画终端。
- 不落盘。理由：mode 是**视图选择**，不是启动参数——重建 pane 后由用户再选一次即可；写进 `session.json` 反而要处理「恢复的 pane 里 agent 是不是同一个会话」这种无解问题。
- registry 挂在 `WorkspaceTerminalRegistry` 上，因为**终端面板和配对宿主都要回答同一个问题**（「这个 pane 什么模式」），而两者本来就共享它。

### 3.2 会话文件怎么定位

`ChatTranscriptSession`（`lib/services/chat/chat_transcript_session.dart`）：

1. 用 pane 的 cwd（OSC 7 优先，WSL 走 `windowsPathToWsl` 还原成 `/home/...`；见 `_directoryForEntry`）+ 该 pane 的 `RuntimeTarget`。
2. 交给已有的 `AgentCliSessionService`（就是「恢复会话」菜单用的那个）扫该机器上 5 个 CLI 的会话库，按下面的规则挑一条。
3. adapter 顺带返回 `filePath`（本次新增字段），所以拿到记录就能直接读文件，不用按家目录规则反推路径。

挑哪一条，两级：

| 级别 | 条件 | 说明 |
|---|---|---|
| own | `createdAt >= paneStart - 2min` | pane 自己的 PTY 启动的会话。`createdAt` 来自会话库本身：pi 家族在文件名里（`2026-11-09T13-14-26-493Z_<id>.jsonl`），Claude 系在第一条记录的 `timestamp` 上。 |
| borrowed | 只有 `updatedAt >= paneStart - 2min` | `--resume` 恢复的会话保留原始创建时间，只能靠 mtime 认领。 |

**为什么不能只看 mtime**：另一个窗口里的会话只要还在跑，mtime 就一直更新，于是「最新的那条」永远指向别人。曾经因此出现过「聊天视图显示了内容，但发消息毫无反应」——视图读的是另一个窗口的会话，消息写进了自己 pane 的 agent，两边对不上。

**发送即校准**（`markPromptSent`）：发送后 20 秒内，如果当前文件里没出现这条 prompt，就去扫同目录最近 3 分钟内改动过的其它会话文件，谁的**最后一条 user 记录**等于这条 prompt，谁就是这个 pane 的真身，直接重绑并在同一次轮询里渲染出来。CLI 一收到输入就落盘，所以这是最可靠的判据——猜测只能在第一条消息之后自我纠正。

**送不到就说话**：发送后 5 秒内会话文件没有出现这条 prompt，输入框上方显示错误、文本还回输入框（`chatPanePromptUndelivered`）。会话库是唯一证据，静默吞掉是最差的结果。

自动重绑只覆盖桌面端面板：手机端的输入走终端字节流，宿主分不清「聊天模式里打的一句话」和「终端里敲的键」，所以手机上发送不会触发校准（读到的内容会随桌面端的校准一起对）。

### 3.3 为什么是轮询而不是 watch

WSL 后端的每个文件操作都是一次 `wsl.exe` 进程（`docs/wsl-fs-helper-design.md` 的老问题）。`FsWatcher` 只有本地/部分后端支持，WSL 上事件驱动反而更贵。所以：固定 800ms 轮询 `stat`，size/mtime 没变就什么都不做；变了才整文件重读 + 重解析。

整文件重读而非增量追加，是因为 CLI 会**改写**前面的记录（title、cost、流式 assistant 块），追加式解析会漂。实际会话文件几百 KB，重解析只要几毫秒。

### 3.4 行模型

`ChatTranscriptRow{ id, kind, text, toolName, detail, running, at }`，`kind ∈ {user, assistant, thought, tool, notice}`。

- `id` 稳定（`<messageId>#<块序号>`），重新解析时同 id 原地替换，界面不会因为一次轮询就重建整个列表。
- 工具行 = 名字 + 一行目标（`Bash  flutter test`），输出折叠；`running` 表示还没等到 `tool_result`。
- `thinking` 块折叠成「思考」；`isSidechain`（子 agent 的对话）、`attachment`、`hook` 摘要、`cost-state` 等噪声一律跳过。
- 工具输出截到 4000 字符：它要发给手机，不能让一次 `cat` 把整条链路撑爆。

### 3.5 解析器现状

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
- 手机端：`session.list` 的每条带 `mode`；镜面页每秒 `chat.read` 一次（一次往返同时回答「什么模式」和「有什么内容」），chat 模式就复用同一个 `ChatTranscriptPane`，输入框写进同一个 PTY。桌面在镜像期间切换模式，手机会在下次轮询跟着切——不需要重连，因为 agent 没被打断。

---

## 5. 本次落地与待办

已实现（`client/`）：

- `services/chat/chat_transcript_row.dart` — 行模型 + 线上 JSON
- `services/chat/chat_transcript_parser.dart` — claude/qoder JSONL → 行
- `services/chat/chat_transcript_session.dart` — 定位 + 轮询 + 解析 + `busy`
- `services/chat/chat_transcript_registry.dart` — pane 模式
- `pages/home_workspace/workspace/chat/chat_transcript_pane.dart` — 对话视图 + 输入框
- 面板工具栏切换按钮；`AgentCliSessionRecord.filePath`
- 配对协议：`session.list` 带 `mode`、`chat.read` 返回 `{mode, transcript}`；镜面页按模式二选一
- 测试：parser 9 例、session 7 例、pane 6 例、rpc 4 例

### 手机端验证（MuMu 平板模拟器，真机级）

用 `tool/pair_host_probe.dart` 编译成 release 宿主（`flutter build windows --release -t tool/pair_host_probe.dart`），
`TP_PROBE_ADDR=127.0.0.1` + `adb reverse tcp:47821 tcp:47821`，平板模拟器配对后：

- `probe-chat` 在手机上渲染为对话（用户气泡 / 折叠「思考」/ 助手正文 / 折叠工具行 / 输入框），**没有**终端工具条；
- `probe-alpha` 同时仍是终端 + 工具条 —— 模式逐 pane 生效，不是全局开关；
- 手机输入「hello demo from mumu」→ 宿主把这一轮写进 JSONL → 手机轮询后出现该气泡与回复（同一条 PTY，agent 没被打断）；
- 宿主切换该 pane 的模式（probe 用文件哨兵模拟桌面点按钮）→ 手机下一次轮询跟着切：终端 ↔ 对话来回都验证过，无需重连；
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