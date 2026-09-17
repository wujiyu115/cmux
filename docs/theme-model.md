# 颜色主题统一方案(VS Code 化)

**状态:设计稿,实现中。** 把「主题色」「终端配色」两个互不联动的旋钮合并为一个颜色主题选择器;主题自带亮暗,亮/暗槽各选一个,对齐 VS Code `workbench.colorTheme` + `preferredLight/DarkColorTheme` + `autoDetectColorScheme` 模型。

## 1. 现状(问题)

配色相关设置分散在两张卡、三个字段:

| 设置 | 字段 | 位置 |
|---|---|---|
| 主题模式 light/dark/system | `themeMode` | 外观卡 |
| 主题色(5 固定预设 + `terminal`) | `themeColorPreset` | 外观卡 |
| 终端配色(`adaptive` + 23 目录主题 + 导入) | `terminalThemeMode` | 独立「终端主题」卡 |
| 终端自定义颜色 | `useCustomTerminalColors` + `terminalColorOverrides` | 同上 |

「文件浏览配色」不是独立旋钮:文件树/侧栏底色永远是 `surfaceContainerLow`(从当前 ColorScheme 派生)。

**复杂感来源**:双向派生机制都已存在但互不联动 —— `terminalThemeMode='adaptive'` 时终端从 UI ColorScheme 派生(`terminal_theme_mapper.dart` `_legacyTerminalTheme`);`themeColorPreset='terminal'` 时整套 UI 从终端主题像素级反推(`app_theme.dart` `_canDeriveFromTerminal` → `terminalDerivedColorScheme`)。用户选了终端目录主题后 UI 不跟(除非再手动把主题色切到「跟随终端」),选了 UI 预设后终端又回 adaptive。两个旋钮、四种组合、两种失效态(如 `preset='terminal'` + `mode='adaptive'` 回退默认调色板)。

## 2. VS Code 模型(对照)

- 一个 `workbench.colorTheme` 决定一切:UI chrome、终端 ANSI、语法色。每个主题**自带固定亮暗**(`Dark Modern`、`Light Modern`、`Dracula` 是并列条目)。
- `window.autoDetectColorScheme`(默认关)+ `workbench.preferredLightColorTheme` / `preferredDarkColorTheme`:跟随系统时,亮/暗槽各指定一个主题。
- `terminal.integrated.*` 颜色覆盖是高级选项,默认不露出。

## 3. 目标模型

**统一主题注册表**,一个 id 空间:

| 命名空间 | 条目 | 亮暗 |
|---|---|---|
| `ui:{preset}:{light\|dark}` | 5 界面预设 × 2(如 `ui:amber:dark`) | id 编码 |
| 目录主题 id(`dracula`、`nord`、…) | 23 个 | 主题固有(`isLightByLuminance`) |
| legacy(`classicDark`、`highContrast`) | 2 个 | 固有(暗) |
| 导入主题 id | 用户文件 | 固有 |

**语义**:选中一个主题 = 全局生效。
- `ui:*` 主题 → UI 走固定调色板(现 `buildLight/DarkTheme(preset)`),终端 = `adaptive` 派生,文件树随 ColorScheme —— 三者同族。
- 目录/导入/legacy 主题 → 终端用该主题,UI 走 `terminal` 派生链(像素级跟随),文件树随之 —— 三者同族。
- **`terminalThemeMode` 字段消失**:有效终端模式 = `isUiTheme(id) ? 'adaptive' : id`,由 resolver 推导。

**持久化字段**(`LayoutPreferences`):

| 字段 | 处置 |
|---|---|
| `themeMode` | **保留**(light/dark/system ≙ VS Code autoDetect + 手动钉住) |
| `lightThemeId` | **新增**,默认 `ui:amber:light` |
| `darkThemeId` | **新增**,默认 `ui:amber:dark` |
| `themeColorPreset` | **删除** |
| `terminalThemeMode` | **删除** |
| `useCustomTerminalColors` / `terminalColorOverrides` | 保留(高级覆盖,叠加在所选主题的终端色上) |

**解析**(`effectiveThemeId`):
```
mode light  → lightThemeId
mode dark   → darkThemeId
mode system → platformDark ? darkThemeId : lightThemeId
effectiveBrightness = brightnessOf(effectiveThemeId)   // ui:…:light/dark 按 id;目录按 luminance
```
主题亮暗**以主题自身为准**(VS Code 语义):把 `dracula` 放进亮槽 + mode=light 渲染的就是暗色 —— 槽位只是「跟随系统时用哪个」。

**设置 UI**:
- 外观卡「主题」组:主题模式(三段,不变)+ 按模式条件显示「浅色主题」「深色主题」行(mode=system 两行都显示)—— 行尾按钮显示当前主题名,点开**统一主题选择器**(分组列表,复用 `TerminalSchemePicker` 的色板行样式):界面主题(浅/深)/ 终端主题(深/浅)/ 导入主题。
- 「终端主题」卡降级为**高级覆盖**:删除 scheme picker 行(移入统一选择器),保留导入/删除、实时预览、自定义颜色开关、逐槽编辑器。
- `AppearanceControls`(onboarding + 手机端):主题模式 + 颜色主题(写当前模式对应槽)+ 语言。
- 新会话快捷菜单(`workspace_terminal_new_session_menu`)的终端配色子菜单**删除** —— 它暴露的「终端独立配色」概念已不存在,统一入口在设置。

## 4. 迁移(`fromJson` 静态)

新字段缺失时,从旧字段解析单一主题 T 再分槽:

```
T = terminalThemeMode != 'adaptive' ? terminalThemeMode          // 目录/legacy/导入
  : themeColorPreset != 'terminal'  ? 'ui:{themeColorPreset}'    // 固定预设
  : 'ui:amber'                                                    // terminal+adaptive 回退态
lightThemeId = T 为目录/legacy/导入 ? T : 'ui:{preset}:light'
darkThemeId  = T 为目录/legacy/导入 ? T : 'ui:{preset}:dark'
```

- 固定预设用户(多数):亮暗槽 = 该预设的亮/暗版 —— **与今天完全一致**(今天就是一个 preset 渲染两个亮度)。
- 目录主题用户:两槽同 id —— 今天 `preset='terminal'` + `mode=dracula` 在 system 下亮环境会错配回退到默认调色板(`_canDeriveFromTerminal` 亮度校验不过);迁移后恒定渲染 dracula,**行为变化 = 修掉错配**,与「主题自带亮暗」语义一致。
- `themeMode` 原样保留,无迁移。
- `toJson` 只写新字段;旧字段两个版本后可从迁移分支清除(clean cutover:类中直接删)。

## 5. 影响面

### 核心

| 文件 | 改动 |
|---|---|
| `models/layout_preferences.dart` | 删 2 字段加 2 字段;`effectiveThemeId(platformDark)`、`terminalModeForTheme`、`brightnessOfTheme` resolver;迁移 |
| `theme/app_theme.dart` | 新增 `resolveThemeDataFor(themeId, terminalTheme, typography…, iconScale, fonts)`:`ui:*` → 固定调色板按 id 亮度;目录 → `_flexFromTerminalTheme`。`kThemeColorPresetIds`/`normalizeThemeColorPreset` 保留(内部调色板查表) |
| `theme/terminal_derived_scheme.dart` | `resolveUiTerminalTheme` 消费方改为传 resolver 产出的 mode;cache key 随字段更名 |
| `cubits/layout_cubit.dart` | `setThemeColorPreset`/`setTerminalThemeMode` 删;`setLightTheme`/`setDarkTheme` 增;导入/删除主题后的回写改槽位 |

### 消费方(读旧字段的全部改读 resolver)

`main.dart`(选择器 + `_resolveThemes` + MaterialApp theme/darkTheme 槽)、`pages/system/fatal_app_theme.dart`、`services/terminal/terminal_theme_for_launch.dart`、`pages/chat_workbench.dart`、`widgets/workspace_terminal_panel.dart`、`pages/pairing/pairing_mirror_page.dart`、`pages/config/terminal_theme/terminal_theme_config_card.dart`(删 picker 行 + 预览/导入回写改槽)、`widgets/settings/appearance_controls.dart`、`pages/config/layout_appearance_in_layout_section.dart`(槽位行)、`widgets/workspace_terminal/workspace_terminal_new_session_menu.dart`(删配色子菜单)。

### UI 组件

| 文件 | 处置 |
|---|---|
| `widgets/settings/theme_color_preset_picker.dart` | **删除**(chips 选择器被统一列表取代) |
| `pages/config/terminal_theme/terminal_scheme_picker.dart` | 改造为统一 `ColorThemePicker`(增加界面主题组)或新写 + 删旧 |
| 新 `widgets/settings/color_theme_picker.dart` | 统一选择器 dialog:分组(界面·浅/界面·深/终端·深/终端·浅/导入)+ 色板行 + 选中态 |

### l10n

新增:`lightThemeTitle/Description`、`darkThemeTitle/Description`、`colorThemeDialogTitle`、`colorThemeGroupUiLight/UiDark/TerminalDark/TerminalLight/Imported`、`themeVariantLight/Dark`(UI 主题显示名 = 既有 `themePreset*` 名 + 亮/暗后缀,经 `l10n.colorThemeName(id)`)。删除:`themeColorPresetTitle/Description`、`workspaceTerminalThemeAdaptive`、`terminalColorSchemeGroupDark/Light/Legacy`(随被删控件一并清除);`terminalColorSchemeTitle/Description` 保留(导入行仍用,描述改为「管理导入主题 + 逐槽覆盖」)。

### 测试

| 文件 | 影响 |
|---|---|
| `test/models/layout_preferences_default_test.dart` | `terminalThemeMode` 合法性用例 → 迁移表用例(三类旧值 → 槽位) |
| `test/pages/config/terminal_theme_config_card_test.dart` | picker 行为用例移到统一选择器测试;导入/删除/自定义色用例改断言槽位字段 |
| `test/cubits/layout_cubit_preferences_test.dart` | `setThemeMode` 保留;新增 `setLightTheme`/`setDarkTheme` |
| `test/theme/terminal_derived_scheme_test.dart`、`terminal_theme_mapper_test.dart`、`terminal_color_overrides_test.dart` | mapper 入参改 resolver 输出,主题派生逻辑不变 |
| `test/services/editor/*theme*` | 语法色跟随终端主题链路不变,预期无影响 |

### 不受影响

- 终端渲染(`flutter_alacritty`)、`CmuxTerminalTheme`、导入解析器、逐槽覆盖、`UserTerminalThemeRegistry`。
- `terminalDerivedColorScheme` 派生数学(cmux 移植)一字不动 —— 只是触发条件从「preset=='terminal'」变为「主题 id ∈ 目录」。
- 字号/缩放模型(docs/font-size-model.md)完全正交。

## 6. 明确不做的

- **不做逐面板配色**(终端/文件树独立于 UI):与统一目标相反。
- **不给界面预设造「终端主题版」**:UI 预设主题下终端继续 adaptive 派生(今天的行为)。
- **不迁移用户自定义槽位覆盖为独立主题**:overrides 继续叠加在所选主题上。
- **不引入 VS Code 的 settings.json 式逐 token 颜色定制**:现有逐槽编辑器已覆盖。
