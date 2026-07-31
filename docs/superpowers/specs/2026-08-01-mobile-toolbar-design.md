# 移动端终端快捷键工具栏（子项目 A）

日期：2026-08-01
状态：设计已确认，待实现
来源参照：`/Users/yitouxiaomaolv/git/Nexterm`（同为 Flutter 应用，Riverpod + xterm）

## 背景

cmux 移动端（iOS/Android）不是 SSH 客户端，而是 **pairing 镜像端**：`PairingMobileShell` → `PairingMirrorPage` 通过 WebSocket + E2EE 把按键送到桌面宿主的 PTY（`app_router.dart:86-89`、`platform_utils.dart:26`）。当前移动端只有一个硬编码的 `_MirrorBar`（`pairing_mirror_page.dart:124`），内含一个 Ctrl-C 按钮和一行提示文字，无法输入 Esc / Tab / 方向键 / F 键，TUI 与 shell 编辑几乎不可用。

本 spec 只覆盖 **快捷键工具栏**。整体移植拆为四个子项目，按序推进：

| # | 子项目 | 依赖 |
|---|---|---|
| **A（本文）** | 快捷键工具栏：16 组键、粘性修饰键、长按连发、自定义页、使用计数 | — |
| B | Composer 文本面板 + DPad 悬浮方向盘 + 底部三选一切换器 | A |
| C | 语音输入三后端（system / 火山豆包 / 阿里 NLS） | B |
| D | pairing 文件传输 RPC + 图片上传 | B |

## 目标

1. `PairingMirrorPage` 底部出现 44px 快捷键条，布局与 Nexterm 一致（左侧横滚键组 + 右侧固定「收起键盘」）。
2. 16 组 × 4 键全部可用，默认只显示前 4 组；顺序、可见组数、使用次数持久化。
3. Ctrl / Alt 为**一次性粘性修饰键**，互斥，发送后自动复位，转义序列按 xterm 修饰位重写。
4. 键位编码为纯函数，可完整单测，不依赖 Flutter 与 pairing。

### 非目标

- 桌面端工作台（`WorkspacePage`）不改；工具栏只在 pairing 镜像端出现。
- 不做 Composer / DPad / FunctionPanel（子项目 B）。
- 不做用户自定义新键（只能对内置组排序、增减可见数量），Nexterm 亦然。

## 架构

四个单元，各自边界清晰、可独立测试：

```
ToolbarKeyDefinition (纯数据)
        │
        ▼
encodeToolbarKey(bytes, ctrl:, alt:) → List<int>   (纯函数)
        │
        ▼
MobileToolbarCubit ── sendInput: void Function(List<int>)  ← 注入 PairingClientCubit.sendInput
        │        └── MobileToolbarRepository (shared_preferences)
        ▼
MobileKeyboardToolbar / MobileToolbarCustomizePage  (UI)
```

### 1. 键位数据 —— `client/lib/models/toolbar_key.dart`

```dart
class ToolbarKey {
  final String id;
  final String label;
  final ToolbarKeySpecial? special; // ctrl | alt | paste
  final List<int> bytes;
  bool get repeatable => id.startsWith('arrow_');
}
class ToolbarKeyGroup { final String id; final List<ToolbarKey> keys; }
List<ToolbarKeyGroup> get defaultToolbarGroups;   // 16 组
```

组名不入数据（走 l10n 查表 `toolbarGroupLabel(id, l10n)`），键面标签入数据。

默认组顺序与字节（照搬 Nexterm `toolbar_key_definition.dart:110-207`）：

| # | 组 id | 键 → 字节 |
|---|---|---|
| 1 | `arrows` | `←` `ESC[D` / `↑` `ESC[A` / `↓` `ESC[B` / `→` `ESC[C` |
| 2 | `clipboard` | `Paste`（特例，无字节）/ `^U` 0x15 / `^K` 0x0B / `^Y` 0x19 |
| 3 | `terminal_ctrl` | `Esc` 0x1B / `Tab` 0x09 / `Ctrl`（修饰）/ `Alt`（修饰） |
| 4 | `signals` | `^C` 0x03 / `^D` 0x04 / `^Z` 0x1A / `^S` 0x13 |
| 5 | `symbols1` | `/` `\|` `~` `-` |
| 6 | `navigation` | `Home` `ESC[H` / `PgUp` `ESC[5~` / `PgDn` `ESC[6~` / `End` `ESC[F` |
| 7 | `editing` | `Del` `ESC[3~` / `Ins` `ESC[2~` / `@` / `?` |
| 8 | `search` | `^R` 0x12 / `^G` 0x07 / `^N` 0x0E / `^P` 0x10 |
| 9 | `punctuation` | `=` `:` `;` `!` |
| 10 | `symbols2` | `*` `$` `%` `^` |
| 11 | `brackets1` | `<` `>` `(` `)` |
| 12 | `brackets2` | `{` `}` `[` `]` |
| 13 | `fkeys1` | F1–F4 = `ESC O P/Q/R/S` |
| 14 | `fkeys2` | F5 `ESC[15~` / F6 `ESC[17~` / F7 `ESC[18~` / F8 `ESC[19~` |
| 15 | `fkeys3` | F9 `ESC[20~` / F10 `ESC[21~` / F11 `ESC[23~` / F12 `ESC[24~` |
| 16 | `advanced` | `^_` 0x1F / `^L` 0x0C / `Alt-r` `1B 72` / `^X^X` `18 18` |

默认可见组数 = 4。

### 2. 编码器 —— `client/lib/services/terminal/toolbar_key_encoder.dart`

纯函数，零 IO：

```dart
List<int> encodeToolbarKey(List<int> bytes, {bool ctrl = false, bool alt = false});
```

规则（Nexterm `keyboard_toolbar.dart:57-117` 语义）：

- 无修饰 → 原样返回。
- `ctrl` + 单字节：字节在 `0x40..0x7F` 时返回 `byte & 0x1F`（`'a'`→0x01）；否则原样返回。
- `ctrl` + 多字节（转义序列）→ 按 xterm 修饰位 **5** 重写。
- `alt` + 单字节 → `[0x1B, byte]`。
- `alt` + 多字节 → 按 xterm 修饰位 **3** 重写。
- 修饰位重写：`ESC O <f>` → `ESC [ 1;<m> <f>`；`ESC [ <f>`（字母结尾）→ `ESC [ 1;<m> <f>`；`ESC [ <n> ~` → `ESC [ <n>;<m> ~`；无法识别的形状原样返回。

`ctrl` 与 `alt` 同真的情况由 cubit 保证不发生（互斥），编码器仍定义为 ctrl 优先。

### 3. `MobileToolbarCubit` —— `client/lib/cubits/mobile_toolbar_cubit.dart`

状态：`{List<String> groupOrder, int visibleGroupCount, Map<String,int> usage, bool ctrl, bool alt}`。

依赖注入：`void Function(List<int>) sendInput` + `MobileToolbarRepository`。**cubit 不认识 pairing**，实参为 `PairingClientCubit.sendInput`（`pairing_client_cubit.dart:399`），B/C/D 复用同一签名。

行为：

- `tapKey(id)`：`special` 为 `ctrl`/`alt` → 切换修饰位（互斥：置一即清另一）并 return；为 `paste` → 见下；否则 `sendInput(encodeToolbarKey(key.bytes, ctrl:, alt:))`，`usage[id]++`，然后修饰位复位。
- `paste`：读 `Clipboard.getData(Clipboard.kTextPlain)`，**`\r\n`/`\n` 归一化为 `\r`**（与 `ImeSession._commit` 同一约定 —— 终端要 CR 才算提交），UTF-8 编码后发送；**绕过修饰位、不计入 usage**。
- 修饰位为一次性（one-shot），不锁定；任何普通键发送后 `reset()`。
- 可见组数改变 / 顺序改变 → 立即落盘；`usage` 1s debounce 合并落盘，`close()` 时 flush。

### 4. 持久化 —— `client/lib/repositories/mobile_toolbar_repository.dart`

照 `pairing_settings_repository.dart:117` 形状：抽象类 + `SharedPreferences` 实现 + `InMemory` 实现（测试）。单键 JSON blob：

```
key: teampilot.mobile_toolbar.v1
{ "groupOrder": ["arrows","clipboard","terminal_ctrl","signals", ...],
  "visibleGroupCount": 4,
  "usage": { "ctrl_c": 37 } }
```

读取时：未知 group id 丢弃；内置组缺失则**按内置顺序追加到尾部**（以后加新组不会让老用户顺序失效）；`visibleGroupCount` 夹取到 `1..groupOrder.length`。

### 5. UI

`client/lib/pages/pairing/mobile_toolbar/`（route-only UI，遵循 AGENTS.md 分层；不进 `shared_ui`，因为这是 pairing 路由专属而非跨路由原语）：

- `mobile_keyboard_toolbar.dart` —— 替换 `pairing_mirror_page.dart:111` 的 `_MirrorBar`，仍位于 `Column` 中 `Expanded(TerminalView)` 之下，键盘由 `Scaffold` 默认 inset 顶起（推起、不覆盖，与 Nexterm 一致）。
- `mobile_toolbar_customize_page.dart` —— `ReorderableListView` 排序 + 可见组数调节 + 高频键展示 + 重置；入口挂在已有 `mobile_settings_sheet.dart:61`。

现有 Ctrl-C 按钮并入 `signals` 组的 `^C` 键，`AppKeys.pairingMirrorCtrlCButton` 挂到该键，老 widget 测试不破。

#### 尺寸（照搬）与配色（映射到 cmux）

仓库无 `ThemePalette`，`TpThemeData` 只暴露 `ColorScheme`（`tp_theme_data.dart:85`），沿用 `_MirrorBar` 现有用法：

| 角色 | Nexterm | cmux |
|---|---|---|
| 条背景 | `bgElevated` | `cs.surface` |
| 键背景 | `surfaceSolid` | `cs.surfaceContainerHighest` |
| 修饰激活 | `accent` / 反色字 | `cs.primary` / `cs.onPrimary` |
| 键标签 | `fg` | `cs.onSurface` |
| 分隔线 | `border` | `cs.outlineVariant` |

尺寸：条高 44；键 `minWidth 40` + 水平 padding 6 + `margin h2 v6`（视觉高 32）+ 圆角 6；组间分隔线 `1×24`，`margin h4`；左侧 `Expanded(SingleChildScrollView(horizontal, BouncingScrollPhysics, padding h4))`；右侧固定「收起键盘」按钮 `44×44`（`Icons.keyboard_hide`）；标签 `bodyMedium` + `w600` + `height: 1`。

行为细节：

- 每次发送 `HapticFeedback.lightImpact()` —— 仓库首次使用（`client/lib` + `shared_ui` 当前 0 处）。
- `arrow_*` 长按连发：`onLongPressStart` 立即发一次 + `Timer.periodic(80ms)`；抬手 / `dispose` 取消。
- **收起键盘后工具栏仍可用**：键走 cubit → `sendInput`，不经 `FocusNode`/IME。
- 底部内边距沿用 `SafeArea(top: false)`；键盘弹起时 `MediaQuery.padding.bottom` 自动归零，无需手算 `viewInsets`。

### 6. l10n

`client/lib/l10n/app_en.arb` + `app_zh.arb` 各加：16 个组名（`mobileToolbarGroupArrows` …）、自定义页 5 条（标题 / 可见组数 / 高频键 / 拖拽提示 / 重置）、收起键盘 tooltip。**键面标签不做 i18n**（`^C` / `Esc` / `F1` / `/` 是符号与终端惯例，与 Nexterm 一致）。改完 ARB 跑 `dart run tool/gen_warmup_glyphs.dart`。

## 错误处理

- 剪贴板为空或读取失败 → 不发送、不报错（静默，与 Nexterm 一致）。
- pairing 未连接 / 无活动订阅 → `PairingClientCubit.sendInput` 现有行为即丢弃；工具栏不额外提示。
- `shared_preferences` 读取到损坏 JSON → 回落到内置默认，记 `AppLogger` 诊断，不阻塞 UI。
- 持久化写入失败 → 记 `AppLogger`，UI 状态保留（内存内仍生效）。

## 测试

- `toolbar_key_encoder_test.dart`（重点）：裸字节透传；`ctrl + 'a'(0x61)` → `0x01`；ctrl 遇 0x40 以下字节原样；`ctrl + ESC[A` → `ESC[1;5A`；`alt + '/'` → `1B 2F`；`alt + ESC O P` → `ESC[1;3P`；`alt + ESC[5~` → `ESC[5;3~`；`^X^X` 双字节不被 ctrl 改写；无法识别的转义形状原样返回。
- `mobile_toolbar_cubit_test.dart`：Ctrl/Alt 互斥；发送后一次性复位；usage 只对普通键计数（ctrl/alt/paste 不计）；paste 多行 `a\nb` → `a\rb`；顺序/可见数 round-trip；未知 id 丢弃 + 新组补尾；`visibleGroupCount` 夹取。
- `mobile_keyboard_toolbar_test.dart`：默认渲染 4 组；点 `^C`（经 `AppKeys.pairingMirrorCtrlCButton`）发 `[0x03]`；箭头长按重复 ≥2 次；收起键盘按钮 unfocus 后仍能发键。渲染本地化 UI 需按 AGENTS.md 包裹 `AppLocalizations.localizationsDelegates` + `locale: Locale('en')`。
- `mobile_toolbar_customize_page_test.dart`：拖拽后顺序落盘并反映到条上。

## 文件规模预算（AGENTS.md 软上限内）

| 文件 | 预计行数 |
|---|---|
| `models/toolbar_key.dart` | ~200 |
| `services/terminal/toolbar_key_encoder.dart` | ~90 |
| `cubits/mobile_toolbar_cubit.dart` | ~180 |
| `repositories/mobile_toolbar_repository.dart` | ~90 |
| `pages/pairing/mobile_toolbar/mobile_keyboard_toolbar.dart` | ~250 |
| `pages/pairing/mobile_toolbar/mobile_toolbar_customize_page.dart` | ~220 |

## 已知风险

phone → host 方向无背压、无 ack（`ws_transport.dart:23` 为 fire-and-forget，宿主侧 5ms 批处理只作用于 host → phone）。方向键 80ms 连发 ≈ 12.5 帧/秒，每帧一个 WS binary message。首版不做节流；若 LAN 抖动导致方向键滞后堆积，在子项目 B 阶段加客户端节流或 ack 窗口。

## 相关既有修复

同日修复了 iOS/Android 软键盘 Return 只换行不提交的问题（`flutter_alacritty/lib/input/ime_session.dart`：iOS 请求 `TextInputAction.newline`、`performAction` 提交 CR、commit 路径 LF/CRLF → CR）。本 spec 的 `paste` 归一化沿用同一约定。
