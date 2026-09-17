# 字号模型重构方案

**状态：已实现。** 目标是对齐 VS Code 的字号模型，消除「文字大小」与「界面缩放」的语义重叠：字号改为绝对逻辑 px（`uiFontSize` / `monoFontSize`），「界面缩放」基线由 `1/dpr` 改为 `1.0`（dpr 交回 Flutter 原生处理）。迁移在 `LayoutPreferences.fromJson` 内静态完成，文字/图标视觉零变化（间距随文字恢复设计比例）。

## 1. 现状

设置页「外观」卡片已按 5 个子分组组织（主题 / 字体与字号 / 显示缩放 / 语言与区域 / 编辑器行为，见 [layout_appearance_in_layout_section.dart](client/lib/pages/config/layout_appearance_in_layout_section.dart)）。其中与字体/字号相关的设置项共 5 个：

| 设置项 | 持久化字段 | UI 控件 | 作用范围 |
|---|---|---|---|
| 文字大小 | `typographyScale` + `typographyScaleCustomMultiplier` | `TypographyScaleSetting` | UI 文字（不含图标/间距） |
| 界面字体 | `uiFontId` | `FontPreferenceSetting(role: ui)` | UI 字族 |
| 等宽字体 | `monoFontId` | `FontPreferenceSetting(role: mono)` | 终端 / 编辑器 / diff 字族 |
| 等宽字号 | `monoFontScale` | `MonoFontSizeSetting` | 终端 / 编辑器 / diff 字号，**相对文字大小** |
| 界面缩放 | `uiZoomScale` + `uiZoomCustomMultiplier` | `TypographyScaleSetting` | 整体缩放（文字+图标+间距） |

### 问题

1. **「文字大小」与「界面缩放」语义重叠。** 两者档位名完全相同（紧凑/标准/宽松/自定义%）且都乘在文字上：`_resolveThemes` 的 `effectiveTextMult` 乘进 `AppTypographyScale.multiplier`（[main.dart](client/lib/main.dart) `_resolveThemes`），`effectiveZoom` 通过 `UiZoom` 也乘文字（同文件 `build`）。差别仅在前者不带图标和间距。用户调两个旋钮都能让字变大，无法预期选哪个。

2. **等宽字号是三级嵌套。** 最终字号为 `terminalBase × multiplier × terminalMultiplier × monoFontScale`（[app_typography_scale.dart](client/lib/theme/app_typography_scale.dart) `AppTypographyScale.terminal`），四个因子连乘，其中 `multiplier` 已含 OS 基线 ×「文字大小」档位，`monoFontScale` 来自「等宽字号」，改任一个都要靠心算。

3. **`TypographyScaleSetting` 与 `MonoFontSizeSetting` 是两份近乎重复的实现。** 两者都是「档位段选 + 自定义百分比输入」，逻辑同构、代码各写一遍。

## 2. VS Code 的模型（对照基准）

从 VS Code 源码（main 分支，2026-09 核对）读到的实际定义：

| 面 | 字族设置 | 字号设置 | 默认值 / 值域 |
|---|---|---|---|
| 编辑器 | `editor.fontFamily` | `editor.fontSize` | Win `Consolas, 'Courier New', monospace` / Mac `Menlo, Monaco, …` / Linux `'Droid Sans Mono', monospace`；14（Mac 12），clamp 6–100 |
| 终端 | `terminal.integrated.fontFamily`（默认跟随编辑器） | `terminal.integrated.fontSize` | 跟随编辑器 / 14（Mac 12），clamp 6–100 |
| 调试台 | `debug.console.fontFamily` | `debug.console.fontSize` | 独立 |
| Markdown 预览 | — | `markdown.preview.fontSize` | 独立 |
| 窗口整体 | — | `window.zoomLevel` | `0`，**连续数值**（schema `type: 'number'`，可填小数），clamp −8..8；每 +1 = ×1.2（`zoomLevelToZoomFactor = 1.2 ** level`），经 Electron `webFrame.setZoomLevel` 合成器缩放 |
| 编辑器滚轮缩放 | — | `editor.mouseWheelZoom` → `EditorZoom` | 编辑器专属第三层：fontSize ×(1 + 0.1×level)，clamp −5..20 |
| 侧边栏 / 标题栏 | — | **无设置项** | Electron 原生 |

三个关键特征：

1. **字号是绝对 px（CSS px）**，不是相对倍率，没有「相对文字大小」的概念。
2. **每个面独立一对 (family, size)**，编辑器 / 终端 / 调试台互不联动。
3. **只有 `window.zoomLevel` 是窗口级的**，连编辑器终端字号一起缩放。**现代 VS Code 不做 dpr 补偿** —— zoomLevel 默认 0，dpr 由 Chromium 原生处理（早年的自动 dpr-zoom 已移除）。本方案 zoom 基线 `standard = 1/dpr` 是自有设计，**不是** VS Code 对齐项（见 §5 决策 A：本次重构将其移除，px 语义即与 VS Code 完全一致）。

来源：[terminalConfiguration.ts](https://raw.githubusercontent.com/microsoft/vscode/main/src/vs/workbench/contrib/terminal/common/terminalConfiguration.ts)（:43, :210-216）、[fontInfo.ts](https://raw.githubusercontent.com/microsoft/vscode/main/src/vs/editor/common/config/fontInfo.ts)（:234-244 `EDITOR_FONT_DEFAULTS`；:48-50 `EditorZoom` 应用）、[editorOptions.ts](https://raw.githubusercontent.com/microsoft/vscode/main/src/vs/editor/common/config/editorOptions.ts)（:2124-2151 clamp 6–100）、[desktop.contribution.ts](https://raw.githubusercontent.com/microsoft/vscode/main/src/vs/workbench/electron-browser/desktop.contribution.ts)（:203-211 `window.zoomLevel` schema）、[window.ts](https://raw.githubusercontent.com/microsoft/vscode/main/src/vs/platform/window/common/window.ts)（:514-515 `1.2 ** level`）、[nativeWindow.ts](https://raw.githubusercontent.com/microsoft/vscode/main/src/vs/platform/window/electron-browser/window.ts)（:18-19 ±8）、[editorZoom.ts](https://raw.githubusercontent.com/microsoft/vscode/main/src/vs/editor/common/config/editorZoom.ts)。

## 3. 目标模型

保留 5 项，但删 2 加 2 —— 把两个「相对倍率」换成绝对 px：

| # | 设置项 | 持久化字段 | 值域 | 作用范围 | 处置 |
|---|---|---|---|---|---|
| 1 | 界面字体 | `uiFontId` | 目录/已装字族 | UI 字族 | 不变 |
| 2 | 等宽字体 | `monoFontId` | 目录/已装字族 | 终端 / 编辑器 / diff 字族 | 不变 |
| 3 | **界面字号** | `uiFontSize` | 逻辑 px，10–28 | UI 文字 + 控件高度（图标另见 §4） | 替代 `typographyScale` |
| 4 | **等宽字号** | `monoFontSize` | 逻辑 px，8–28 | 终端 / 编辑器 / diff | 替代 `monoFontScale` |
| 5 | 界面缩放 | `uiZoomScale` + `uiZoomCustomMultiplier` | 档位 + 自定义% | 整体（**不再承担 dpr**） | 基线改为 1.0 |

**删除字段**：`typographyScale`、`typographyScaleCustomMultiplier`、`monoFontScale`。
**新增字段**：`uiFontSize`（默认 14）、`monoFontSize`（默认 14）。

字体**不合并**：终端是 `CustomPaint` 自行排格（[terminal_fonts.dart](client/lib/services/terminal/terminal_fonts.dart)），且默认等宽字体 `JetBrainsMono NFM` 带 Nerd Font 图标字形；换成比例字体会导致列错位与图标字形丢失。两个字体选择器视觉上已归入「字体与字号」分组（§1），各自独立过滤候选（`FontCatalog` 已按 `FontRole` 分区）。

### 与 VS Code 的差异

对齐的：px 单位（逻辑 px ≙ CSS px）、每面 (family, size)、编辑器字族 + 字号、终端字号基准、全局缩放概念、OS 显示缩放由系统 dpr 原生承担（不再自行补偿）。

有意保留的差异（2 项）：

| 维度 | VS Code | 本方案 | 理由 |
|---|---|---|---|
| UI 字体 / 字号 | 无设置项 | 有 | 需要控制中文字族与界面文字密度 |
| 编辑器 vs 终端字号 | 分开两个 | 合并为一个「等宽字号」 | 两者共用字族；终端为 `CustomPaint`，联动比拆分更简单 |

## 4. 映射公式

`AppTypographyScale` 的全部字号均为 `base × multiplier` 派生，因此 px → multiplier 只差一个除法，基准取 `bodyMediumBase = 14`：

| 目标 | 现在 | 改为 |
|---|---|---|
| `multiplier`（UI 全部角色） | `resolveRelativeScale(baseline × 档位倍率)`，baseline = `autoTextScaleForSystem(osTextScale, dpr)` | `uiFontSize / 14`（无 OS 基线） |
| `AppTypographyScale.terminal` | `terminalBase × multiplier × terminalMultiplier × monoFontScale` | `monoFontSize` |
| `AppTypographyScale.mono`（编辑器 / diff） | `monoBase × multiplier × monoFontScale` | `monoFontSize` |
| `control`（控件高度，`TpControlMetrics.fromScale`） | 跟随 `multiplier` | 跟随新 `multiplier`（自动） |
| `iconScale`（[tp_icon_sizes.dart](client/packages/shared_ui/lib/src/theme/tokens/tp_icon_sizes.dart) `resolveIconMultiplier`） | `1.32 × (1 + (presetMult − 1) × 0.75)`，OS 基线被显式除掉，再经 `UiZoom(1/dpr)` → **物理尺寸恒定** | 同一阻尼公式（`presetMult` → `uiFontSize/14`），**再除以 dpr**：zoom 基线变 1.0 后保持图标物理尺寸恒定的现有行为 |
| `UiZoom` 有效缩放 | `clampUiZoom((1/dpr) × zoom档位倍率)` | `clampUiZoom(zoom档位倍率)`（基线 1.0；`autoUiZoomForDevicePixelRatio`、`UiZoomBaseline` 随之删除） |
| `TpSpacing`（间距） | 画布 design px × `UiZoom(1/dpr)` → **物理尺寸恒定**（逻辑尺寸 = design/dpr） | 画布 design px × `UiZoom(1)` → **逻辑尺寸恒定**（物理 = design × dpr），与文字同步随系统缩放 |

`terminalMultiplier` 字段在乘法塌缩后失去意义，一并删除（主链路恒传 `1.0`；`kMobileTextScaleBoost` 的 `mobile: true` 调用只存在于测试，属死代码，同删）。

**间距行是 dpr≠1 机器上唯一的可见变化**（HiDPI 下 padding 逻辑尺寸从 design/dpr 变为 design，即与文字恢复设计比例），见 §5 决策 A 的代价说明。

## 5. 决策

两项均取 **A**。

| 议题 | 决策 A | 被否的 B |
|---|---|---|
| px 语义 / OS 缩放 | **逻辑 px（≙ VS Code CSS px），静态迁移。** 丢弃 `autoTextScaleForSystem`；`UiZoom` 基线从 `1/dpr` 改为 `1.0`，dpr 由 Flutter 原生承担。今天的管线里 OS 基线 `B = clamp(O×dpr)` 与 zoom 基线 `1/dpr` 在 O=1 时**恰好互逆**（文字画布 `14×B×档位` × zoom `1/dpr` → 逻辑 `14×档位`，与 dpr 无关），所以基线翻转 + 静态折算对**任意 dpr** 都视觉零变化（文字与图标逐项相等；间距变化见 §4 末行）。 | ① 保留 `1/dpr` 基线、px 当物理值：迁移必须运行时测 dpr/O，存量 prefs 变成机器相关（换显示器字号漂移），且 px 语义偏离 VS Code。② px 相对 OS 缩放：两个旋钮的语义重叠原样保留，违背重构目标 |
| 老值迁移 | **`fromJson` 内静态折算，文字/图标视觉零变化。** 见下表。 | 统一重置为默认 14px，用户重调 |

### 迁移表

迁移必须乘上「文字大小」的档位倍率 `p`（standard 1.0 / compact 0.92 / comfortable 1.08 / custom 取存储 multiplier）——今天的等宽逻辑字号是 `14 × p × monoFontScale`，旧稿的 mono 表漏乘 `p`，已修正：

`文字大小` → `uiFontSize = clamp(round(14 × p), 10, 28)`：

| 老值 | 新 `uiFontSize` |
|---|---|
| `standard`（p=1.0） | 14 |
| `compact`（p=0.92） | 13 |
| `comfortable`（p=1.08） | 15 |
| `custom`（p=m） | `round(14m)`，clamp 10–28 |

`等宽字号` → `monoFontSize = clamp(round(14 × p × s), 8, 28)`（s = 老 `monoFontScale`）：

| 老值（p=standard 时） | 新 `monoFontSize` |
|---|---|
| `1.0`（标准） | 14 |
| `0.85`（小） | 12 |
| `1.15`（大） | 16 |
| 自定义 s | `round(14ps)`，clamp 8–28 |

迁移在 `LayoutPreferences.fromJson` 内做：新字段缺失且旧字段存在时按上表推导；`toJson` 只写新字段，旧字段从类中删除（clean cutover，不留双写）。

### 已知代价（决策 A 的残留，接受）

1. **GNOME 文字缩放（O≠1）不再被跟随。** 今天 `B = clamp(O×dpr)` 会把 OS text-scaling 折进文字；翻转基线后 O 被完全忽略（`AppTextScaleBoundary` 本就在渲染期归零 `textScaler`，main 里的读取只是基线来源）。Linux 上设了 1.25/1.5 文字缩放的用户迁移后文字一次性变小，需手动把 `uiFontSize` 调到 18/21。O≠1 属少数配置，且 28px 上限覆盖到 O=2。
2. **极端小字号被 clamp。** 老 `custom` 下限 0.5 → 7px，新下限 10px；老 mono 极端组合（0.5×0.7）→ ~5px，新下限 8px。仅影响刻意调到极端的用户。
3. **HiDPI 间距比例变化**（§4 末行）：一次性、与文字恢复设计比例，视为修正而非回退。

`注意`：`AppTextScaleBoundary`（[app_text_scale_boundary.dart](client/lib/widgets/app_text_scale_boundary.dart)）已在渲染期把 `MediaQuery.textScaler` 归零；`_resolveThemes` 中对 `systemMq.textScaler` / `devicePixelRatio` 的基线读取随决策 A 全部停止（dpr 仅图标公式仍需，见 §4）。

## 6. 影响面

### 需改动的文件

| 文件 | 改动 |
|---|---|
| `client/lib/models/layout_preferences.dart` | 字段替换（删 3 加 2）+ `fromJson` 静态迁移 + `copyWith` / `toJson` |
| `client/lib/cubits/layout_cubit.dart` | `setTypographyScale` / `setTypographyScaleCustom` / `setMonoFontScale` → `setUiFontSize` / `setMonoFontSize`；`zoomIn/zoomOut` 去掉 `baseline` 参数 |
| `client/lib/theme/app_typography_scale.dart` | 删除 `kMonoFontScale*`、`autoTextScaleForSystem`、`kMobileTextScaleBoost`、`autoUiZoomForDevicePixelRatio`、`terminalMultiplier`；`resolveRelativeScale` / `typographyScaleForPreferences` **保留但更名归 zoom 语义**（`uiZoomScale` 档位解析仍在用：`layout_cubit._currentUiZoomMultiplier`、`main.dart` `effectiveZoom`）；`AppTypographyScale` 改为按 px 构造 |
| `client/lib/main.dart` | 选择器/缓存键换 px 字段；`_resolveThemes` 删 OS 基线、`iconScale` 除以 dpr；`effectiveZoom` 基线 1.0；`UiZoomBaseline` provider 与写入删除 |
| `client/lib/theme/app_text_styles_warmup.dart` | warmup 主题的 multiplier 推导换 px（`_systemTextBaseline` / `resolveRelativeScale` 调用点） |
| `client/lib/pages/system/fatal_app_theme.dart` | `typographyScaleForPreferences(scaleId: layout.typographyScale, …)` → 按 `uiFontSize` 构造（`error_page.dart` 随之不变） |
| `client/lib/pages/config/layout_appearance_in_layout_section.dart` | 「文字大小」「等宽字号」两行换成 px 控件；选择器字段替换 |
| `client/lib/widgets/settings/typography_scale_setting.dart` | 更名为 zoom 专用（`UiZoomSetting`）：仍服务 `uiZoomScale` 档位；文字侧不再使用 |
| `client/lib/widgets/settings/mono_font_size_setting.dart` | 与新的界面字号控件合并为一个共享 px 输入组件（`FontSizeSetting`：−/+ 步进 + 直接输入 + px 后缀） |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | 删 `typographyScale*`（**保留** zoom 使用的档位名或复制为 `uiZoom*` 系）、`monoFontSize{Small,Standard,Large,Custom,CustomHint}`；新增 `uiFontSizeTitle/Description`、`monoFontSizeTitle/Description`（px 语义）、px 后缀；**更新 `uiZoomDescription`**（「标准」不再按系统缩放自动匹配，= 100%） |
| `client/lib/l10n/app_localizations*.dart` + `client/lib/widgets/warmup_glyphs.g.dart` | ARB 改动后 `flutter gen-l10n` + `dart run tool/gen_warmup_glyphs.dart`（repo 规则） |
| `client/lib/services/commands/…`（`registerLayoutCommands` 调用点） | `zoomIn/zoomOut` 的 baseline 实参删除 |

### 测试

| 文件 | 影响 |
|---|---|
| `test/cubits/layout_cubit_preferences_test.dart` | `monoFontScale` / `kMonoFontScale*` 断言 → px 断言 + **迁移表用例**（旧 json → 新 px，含 p≠1 的 mono 折算） |
| `test/theme/mobile_text_scale_test.dart` | 断言的 `autoTextScaleForSystem` / `kMobileTextScaleBoost` / `terminalMultiplier` 全部删除 → **整个文件删除**（pin 的是被移除的行为，按 repo 规则不重写） |
| `test/theme/ui_zoom_default_test.dart` | `autoTextScaleForSystem` 用例删除；`autoUiZoomForDevicePixelRatio` 用例删除；`resolveRelativeScale`（更名后）与 `standard = 基线` 断言按 zoom 语义保留/改写 |
| `test/widgets/settings/mono_font_size_setting_test.dart` | 控件换 px 后重写（并入 `FontSizeSetting` 测试） |
| `test/services/commands/layout_command_registrar_test.dart` | `zoomIn(baseline:)` 签名变化 |
| `test/widgets/settings/font_preference_setting_test.dart` | 字体选择器不变，应无影响 |

### 不受影响

- `font_catalog.dart`、`font_preference_setting.dart`、`app_font_resolver.dart`、`app_font_loader.dart` —— 字体部分完全不动。
- `services/terminal/terminal_fonts.dart`、`services/editor/file_editor_theme.dart` —— 继续读 `AppTypographyTheme.terminal` / `.mono`，只是取值来源改变。
- `UiZoom` 组件本体（`ui_zoom.dart`）—— 只是传入的 scale 基线变化。

## 7. 明确不做的

- **不合并界面字体与等宽字体**：终端排格与 Nerd Font 图标字形依赖等宽面，合并会破坏列对齐。
- **不拆分编辑器与终端字号**：与 VS Code 的差异是有意为之，见 §3。
- **不引入 `debug.console` / `markdown.preview` 级别的独立字号**：无对应载体。
- **不跟随 VS Code 的 `1.2^level` 整数档 zoom**：保留现有连续档位与 `clampUiZoom(0.5..1.5)`，避免迁移破坏。
- **不引入 `editor.mouseWheelZoom` 式临时缩放层**：Ctrl+滚轮终端缩放如有需求另议。
