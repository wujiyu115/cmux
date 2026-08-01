# 移动端 Composer 文本面板（子项目 B）

日期：2026-08-01
状态：设计已确认，待实现
参照：`/Users/yitouxiaomaolv/git/Nexterm`（`lib/features/terminal/ui/widgets/composer_panel.dart`）
前置：子项目 A 已合入 main（`docs/superpowers/specs/2026-08-01-mobile-toolbar-design.md`）

## 背景

A 给了移动端 pairing 镜像一条 44px 快捷键条，单键输入解决了。但手机上敲一条长命令仍然痛苦：终端逐字回显、无法回退编辑、软键盘的 Return 直接提交（A 期修复后）意味着写错只能重来。

Composer 是一个多行文本面板：先在本地把命令编辑好，再一次性发给宿主 PTY。它同时是子项目 C（语音识别结果落在这里再发送）与 D（上传后的远端路径插入这里）的宿主，所以先于二者实现。

## 目标

1. 镜像页底部在 **快捷键条** 与 **Composer 面板** 之间二选一切换，切换入口是键条上的气泡按钮。
2. Composer 支持多行编辑、一键发送、可切换「发送时是否追加回车」。
3. 草稿在面板切换之间保留，随镜像页销毁而丢弃。
4. 空文本 + 回车模式 = 发一个 CR —— 键条 16 组里没有 Enter 键，这是不依赖软键盘的唯一「按回车」入口。

### 非目标

- 附件 `+` 按钮（子项目 D）、麦克风（子项目 C）。按钮行预留 `Spacer()` 位置，两者各自插入。
- DPad 悬浮方向盘 —— 用户已明确去掉，不在本 spec 也不在后续。
- 草稿落盘。命令可能带密钥或路径，持久化增加泄露面；每次进页面从空开始。
- `chatMode` 落盘。每次启动回到「回车提交」这个安全默认。

## 架构

### 状态归属

`MobileToolbarCubit`（`lib/cubits/mobile_toolbar_cubit.dart`）新增：

```dart
enum MobileInputMode { keys, composer }

// MobileToolbarState 新字段
final MobileInputMode mode;   // 默认 keys
final bool chatMode;          // 默认 true，不落盘

// MobileToolbarCubit 新方法
void setMode(MobileInputMode mode);
void toggleComposer();        // keys <-> composer
void toggleChatMode();
void sendText(String text, {required bool submit});
```

模式是跨 widget 共享状态（键条上的按钮 + 页面决定渲染谁），因此进 cubit 而非 `setState`（AGENTS.md：状态只用 `flutter_bloc`）。

`chatMode` 放 state 而非面板 widget，是为了发送逻辑与按钮着色读同一个值，且 A 期已给 `MobileToolbarState` 建立了「非持久化 UI 状态」（`ctrl`/`alt`）的先例。

`sendText` 语义：
- 文本非空：`utf8.encode(terminalizeNewlines(text))`，`submit` 为真再追加 `0x0d`。
- 文本为空且 `submit`：只发 `[0x0d]`。
- 文本为空且不 `submit`：不发送。
- **不受 `ctrl`/`alt` 影响、不消耗修饰位、不计入 usage** —— 与 `paste` 同一约定。
- 发出的 list 与 `tapKey` 一样包 `List.unmodifiable`。

多行文本里的 LF 统一成 CR，等于逐行执行，与工具栏粘贴一致。

### 草稿归属

`TextEditingController` 与 `FocusNode` 由 `_PairingMirrorPageState` 持有并 `dispose`，以参数传入面板。切到键条时面板 widget 销毁但 controller 存活，切回来文字还在；退出镜像页时随页面销毁。

文本**不进 cubit state** —— 否则每敲一个字符就 emit 一次，A 期刚为「每次按键重画键帽」加了 `buildWhen`，不该再引入同类问题。

### 文件

| 文件 | 职责 |
|---|---|
| `lib/pages/pairing/mobile_toolbar/mobile_composer_panel.dart`（新建，~200 行） | 面板 UI：输入框 + 按钮行。无 IO，不认识 pairing。 |
| `lib/cubits/mobile_toolbar_cubit.dart`（改，+~80 行） | `MobileInputMode`、`chatMode`、`sendText`。 |
| `lib/pages/pairing/mobile_toolbar/mobile_keyboard_toolbar.dart`（改） | 右侧新增气泡切换按钮，顺序 `[气泡] [齿轮] [收起键盘]`。 |
| `lib/pages/pairing/pairing_mirror_page.dart`（改） | 持有 controller/focus；底部按 `state.mode` 二选一渲染。 |
| `lib/utils/ui/app_keys.dart`（改） | 面板与按钮的测试键。 |
| `lib/l10n/app_en.arb` / `app_zh.arb`（改） | 6 条文案。 |

## UI

容器：`cs.surface` 底 + 0.5px 上边框 `cs.outlineVariant`，padding `12,10,12,10`，外套 `SafeArea(top: false)`（键盘弹起时 `MediaQuery.padding.bottom` 自动归零，与键条同一处理）。

输入框：`ConstrainedBox(maxHeight: 120)` + `Scrollbar` + `TextField(minLines: 3, maxLines: null)`，`keyboardType: TextInputType.multiline`、`textInputAction: TextInputAction.newline`，填充 `cs.surfaceContainerHighest`、圆角 10、`contentPadding` 水平 14 垂直 10、`isDense: true`、字号 15，hint 色 `cs.onSurfaceVariant`。

按钮行：34×34 圆形，实现为 `TpIconButton(size: 34, borderRadius: 17, iconSize: 18)`，顺序 `[关闭] [收起键盘] [回车模式] —— Spacer —— [发送]`。

| 按钮 | 图标 | 颜色 |
|---|---|---|
| 关闭 | `Icons.close` | 默认 |
| 收起键盘 | `Icons.keyboard_hide` | 默认 |
| 回车模式（开） | `Icons.keyboard_return` | `cs.primary` 底 / `cs.onPrimary` 图标 |
| 回车模式（关） | `Icons.text_fields` | 默认 |
| 发送 | `Icons.arrow_upward` | `cs.primary` 底 / `cs.onPrimary` 图标 |

**一处刻意的反向**：终端里 Return 是提交（A 期修复），Composer 里 Return 是换行、提交靠发送键。Composer 存在的理由就是多行编辑。

## 焦点与键盘交接

打开 composer → post-frame 回调里 `composerFocus.requestFocus()` → 终端 `FocusNode` 失焦 → `TerminalView._handleImeFocusChange` 卸掉 `ImeSession`，避免两个 IME 客户端抢同一个软键盘。

关闭 composer → 只 `unfocus()`，**不主动把焦点还给终端**。`TerminalView` 对外只有 `TerminalViewState.requestTerminalFocus()`，要拿到它得在页面挂 `GlobalKey<TerminalViewState>`；为一次焦点归还引入跨层耦合不值。点一下终端即恢复（`terminal_view_pointer.dart` 的 pointer 处理已 `requestFocus`），键条本身不依赖焦点。**这是已知行为，不是缺陷。**

## 已知副作用

Composer 比 44px 键条高，终端可用高度被压缩 → `onPtyResize` 触发 resize 帧 → 宿主 PTY reflow。切回键条再 reflow 回来。Nexterm 同样如此，属预期。

## 错误处理

- pairing 未连接 / 无活动订阅：`PairingClientCubit.sendInput` 现有行为即静默丢弃，面板不额外提示（与键条一致）。
- 超长文本：不设上限。pairing input 帧无长度限制（`pairing_frames.dart` 无长度前缀），但方向无背压 —— 若日后出现问题，与 A 期记录的方向键连发风险一并处理。

## 测试

**cubit**（`test/cubits/mobile_toolbar_cubit_test.dart` 追加）
- `toggleComposer` 在 `keys`/`composer` 间往复；`setMode` 幂等。
- `toggleChatMode` 翻转且默认 true。
- `sendText('ls', submit: true)` → `ls\r`；`submit: false` → `ls`。
- `sendText('a\nb', submit: false)` → `a\rb`（LF 归一化）。
- `sendText('', submit: true)` → `[0x0d]`；`sendText('', submit: false)` → 无发送。
- Ctrl 待发时 `sendText` 不消耗修饰位、不计入 usage。
- 发出的 list 不可变（`expect(() => sent.single.add(0), throwsUnsupportedError)`）。

**widget**（`test/pages/pairing/mobile_composer_panel_test.dart` 新建）
- 渲染 hint 与五个按钮。
- 输入 `ls -la` 点发送 → 收到 `ls -la\r`，输入框清空。
- 回车模式关 → 收到 `ls -la`，无 CR。
- 关闭按钮 → cubit 模式回到 `keys`。
- 键条气泡按钮 → 模式变 `composer`（在 `mobile_keyboard_toolbar_test.dart` 追加）。
- 草稿存活：输入文字 → 切 `keys` → 切回 `composer` → 文字还在（用页面持有的 controller 模拟）。

渲染本地化 UI 需按 AGENTS.md 包 `AppLocalizations.localizationsDelegates` + `locale: Locale('en')`。

## l10n

`app_en.arb` / `app_zh.arb` 各加：

| key | en | zh |
|---|---|---|
| `mobileComposerHint` | Type a command | 输入命令 |
| `mobileComposerOpen` | Compose text | 文本输入 |
| `mobileComposerClose` | Close composer | 关闭输入面板 |
| `mobileComposerSend` | Send | 发送 |
| `mobileComposerSubmitOn` | Send with Return | 发送时回车 |
| `mobileComposerSubmitOff` | Send without Return | 发送不回车 |

改完跑 `dart run tool/gen_warmup_glyphs.dart`；若生成的 `AppLocalizations` 落后，跑 `flutter gen-l10n`（A 期遇到过一次生成产物滞后）。
