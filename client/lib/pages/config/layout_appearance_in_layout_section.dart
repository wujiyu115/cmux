import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/layout_preferences.dart';
import '../../theme/app_typography_scale.dart';
import '../../theme/font_catalog.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/settings/font_preference_setting.dart';
import '../../widgets/settings/font_size_setting.dart';
import '../../widgets/settings/color_theme_picker.dart';
import '../../widgets/settings/ui_zoom_setting.dart';
import '../../theme/terminal/user_terminal_theme_registry.dart';

/// Tightened top inset for the in-card group labels: each [TpPreferenceRow]
/// already carries 16px of vertical padding, so the default header padding
/// (top 20) would leave a visibly larger gap than between plain rows.
const EdgeInsets _groupHeaderPadding = EdgeInsets.fromLTRB(20, 12, 20, 4);

class LayoutAppearanceInLayoutSection extends StatelessWidget {
  const LayoutAppearanceInLayoutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<LayoutCubit>();

    return BlocSelector<
      LayoutCubit,
      LayoutState,
      (
        String,
        String,
        String,
        double,
        String,
        String,
        double,
        String,
        double,
        String,
      )
    >(
      selector: (state) {
        var themeMode = state.preferences.themeMode;
        if (themeMode != 'light' &&
            themeMode != 'dark' &&
            themeMode != 'system') {
          themeMode = 'system';
        }
        return (
          themeMode,
          state.preferences.lightThemeId,
          state.preferences.darkThemeId,
          state.preferences.uiFontSize,
          normalizeUiFontId(state.preferences.uiFontId),
          normalizeMonoFontId(state.preferences.monoFontId),
          state.preferences.monoFontSize,
          normalizeUiZoomScale(state.preferences.uiZoomScale),
          state.preferences.uiZoomCustomMultiplier,
          languagePreferenceUiValue(state.preferences.locale),
        );
      },
      builder: (context, appearance) {
        final (
          themeMode,
          lightThemeId,
          darkThemeId,
          uiFontSize,
          uiFontId,
          monoFontId,
          monoFontSize,
          uiZoomScale,
          uiZoomCustomMultiplier,
          langValue,
        ) = appearance;
        return BlocSelector<LayoutCubit, LayoutState, WorkspaceEntryMode>(
          selector: (state) => state.preferences.workspaceEntryMode,
          builder: (context, workspaceEntryMode) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TpSectionHeader(title: l10n.appearance),
                // --- 主题 ---
                TpSectionHeader(
                  title: l10n.theme,
                  padding: _groupHeaderPadding,
                ),
                TpPreferenceRow(
                  title: l10n.themeModeTitle,
                  subtitle: l10n.themeModeDescription,
                  trailing: TpSegmentedPicker<String>(
                    segments: [
                      TpSegmentedOption<String>(
                        value: 'light',
                        label: l10n.themeLight,
                        icon: Icons.light_mode_outlined,
                      ),
                      TpSegmentedOption<String>(
                        value: 'dark',
                        label: l10n.themeDark,
                        icon: Icons.dark_mode_outlined,
                      ),
                      TpSegmentedOption<String>(
                        value: 'system',
                        label: l10n.themeSystem,
                        icon: Icons.desktop_windows_outlined,
                      ),
                    ],
                    selected: themeMode,
                    onChanged: controller.setThemeMode,
                  ),
                  showDividerBelow: true,
                ),
                if (themeMode != 'dark')
                  _ColorThemeRow(
                    title: l10n.lightThemeTitle,
                    subtitle: l10n.lightThemeDescription,
                    themeId: lightThemeId,
                    brightness: Brightness.light,
                    onSelect: controller.setLightTheme,
                    showDividerBelow: themeMode == 'system',
                  ),
                if (themeMode != 'light')
                  _ColorThemeRow(
                    title: l10n.darkThemeTitle,
                    subtitle: l10n.darkThemeDescription,
                    themeId: darkThemeId,
                    brightness: Brightness.dark,
                    onSelect: controller.setDarkTheme,
                    showDividerBelow: false,
                  ),
                // --- 字体与字号 ---
                TpSectionHeader(
                  title: l10n.appearanceGroupFonts,
                  padding: _groupHeaderPadding,
                ),
                TpPreferenceRow(
                  title: l10n.fontUiTitle,
                  subtitle: l10n.fontUiDescription,
                  trailing: FontPreferenceSetting(
                    role: FontRole.ui,
                    value: uiFontId,
                    onChanged: controller.setUiFontId,
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.uiFontSizeTitle,
                  subtitle: l10n.uiFontSizeDescription,
                  trailing: FontSizeSetting(
                    size: uiFontSize,
                    minSize: kUiFontSizeMin,
                    maxSize: kUiFontSizeMax,
                    onChanged: controller.setUiFontSize,
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.fontMonoTitle,
                  subtitle: l10n.fontMonoDescription,
                  trailing: FontPreferenceSetting(
                    role: FontRole.mono,
                    value: monoFontId,
                    onChanged: controller.setMonoFontId,
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.monoFontSizeTitle,
                  subtitle: l10n.monoFontSizeDescription,
                  trailing: FontSizeSetting(
                    size: monoFontSize,
                    minSize: kMonoFontSizeMin,
                    maxSize: kMonoFontSizeMax,
                    onChanged: controller.setMonoFontSize,
                  ),
                  showDividerBelow: false,
                ),
                // --- 显示缩放 ---
                TpSectionHeader(
                  title: l10n.appearanceGroupZoom,
                  padding: _groupHeaderPadding,
                ),
                TpPreferenceRow(
                  title: l10n.uiZoomTitle,
                  subtitle: l10n.uiZoomDescription,
                  trailing: UiZoomSetting(
                    scaleId: uiZoomScale,
                    customMultiplier: uiZoomCustomMultiplier,
                    onScaleIdChanged: controller.setUiZoomScale,
                    onCustomMultiplierChanged: controller.setUiZoomCustom,
                  ),
                  showDividerBelow: false,
                ),
                // --- 语言与区域 ---
                TpSectionHeader(
                  title: l10n.appearanceGroupLanguage,
                  padding: _groupHeaderPadding,
                ),
                TpPreferenceRow(
                  title: l10n.language,
                  subtitle: l10n.languageDescription,
                  trailing: TpCompactSelect<String>(
                    value: langValue,
                    entries: [
                      ('system', l10n.languageSystem),
                      ('en', l10n.languageEnglish),
                      ('zh', l10n.languageChinese),
                    ],
                    itemKeys: const {
                      'system': AppKeys.languageSystemButton,
                      'en': AppKeys.languageEnButton,
                      'zh': AppKeys.languageZhButton,
                    },
                    onChanged: (v) {
                      if (v != null) {
                        controller.setLocale(languagePreferenceStoredLocale(v));
                      }
                    },
                  ),
                  showDividerBelow: false,
                ),
                // --- 编辑器行为 ---
                TpSectionHeader(
                  title: l10n.appearanceGroupEditor,
                  padding: _groupHeaderPadding,
                ),
                TpPreferenceRow(
                  title: l10n.workspaceEntryModeTitle,
                  subtitle: l10n.workspaceEntryModeDescription,
                  trailing: TpSegmentedPicker<WorkspaceEntryMode>(
                    segments: [
                      TpSegmentedOption<WorkspaceEntryMode>(
                        value: WorkspaceEntryMode.home,
                        label: l10n.workspaceEntryModeHome,
                        icon: Icons.home_outlined,
                      ),
                      TpSegmentedOption<WorkspaceEntryMode>(
                        value: WorkspaceEntryMode.lastWorkspace,
                        label: l10n.workspaceEntryModeLastWorkspace,
                        icon: Icons.history,
                      ),
                    ],
                    selected: workspaceEntryMode,
                    onChanged: controller.setWorkspaceEntryMode,
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.markdownOpenModeTitle,
                  subtitle: l10n.markdownOpenModeDescription,
                  trailing: TpCompactSelect<MarkdownOpenMode>(
                    value: context.select<LayoutCubit, MarkdownOpenMode>(
                      (c) => c.state.preferences.markdownOpenMode,
                    ),
                    entries: [
                      (
                        MarkdownOpenMode.preview,
                        l10n.markdownOpenModePreview,
                      ),
                      (
                        MarkdownOpenMode.source,
                        l10n.markdownOpenModeSource,
                      ),
                      (
                        MarkdownOpenMode.remember,
                        l10n.markdownOpenModeRemember,
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) controller.setMarkdownOpenMode(v);
                    },
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.gitChangesViewModeTitle,
                  subtitle: l10n.gitChangesViewModeDescription,
                  trailing: TpSegmentedPicker<GitChangesViewMode>(
                    segments: [
                      TpSegmentedOption<GitChangesViewMode>(
                        value: GitChangesViewMode.tree,
                        label: l10n.gitChangesViewModeTree,
                        icon: Icons.account_tree_outlined,
                      ),
                      TpSegmentedOption<GitChangesViewMode>(
                        value: GitChangesViewMode.flat,
                        label: l10n.gitChangesViewModeFlat,
                        icon: Icons.view_headline_outlined,
                      ),
                    ],
                    selected: context.select<LayoutCubit, GitChangesViewMode>(
                      (c) => c.state.preferences.gitChangesViewMode,
                    ),
                    onChanged: controller.setGitChangesViewMode,
                  ),
                  showDividerBelow: false,
                ),
                TpPreferenceRow(
                  title: l10n.editorPreviewTabsTitle,
                  subtitle: l10n.editorPreviewTabsDescription,
                  trailing: Switch(
                    value: context.select<LayoutCubit, bool>(
                      (c) => c.state.preferences.editorPreviewTabs,
                    ),
                    onChanged: controller.setEditorPreviewTabs,
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.editorWordWrapTitle,
                  subtitle: l10n.editorWordWrapDescription,
                  trailing: Switch(
                    value: context.select<LayoutCubit, bool>(
                      (c) => c.state.preferences.editorWordWrap,
                    ),
                    onChanged: controller.setEditorWordWrap,
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.editorAutoSaveTitle,
                  subtitle: l10n.editorAutoSaveDescription,
                  trailing: TpCompactSelect<EditorAutoSaveMode>(
                    value: context.select<LayoutCubit, EditorAutoSaveMode>(
                      (c) => c.state.preferences.editorAutoSave,
                    ),
                    entries: [
                      (
                        EditorAutoSaveMode.off,
                        l10n.editorAutoSaveOff,
                      ),
                      (
                        EditorAutoSaveMode.afterDelay,
                        l10n.editorAutoSaveAfterDelay,
                      ),
                      (
                        EditorAutoSaveMode.focusChange,
                        l10n.editorAutoSaveFocusChange,
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) controller.setEditorAutoSave(v);
                    },
                  ),
                  showDividerBelow: false,
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// One brightness slot row: shows the active theme name and opens the unified
/// [ColorThemePicker] on tap. Listens to [UserTerminalThemeRegistry] so the
/// picker's imported group stays current; import / delete live in the terminal
/// theme card, so this row never deletes.
class _ColorThemeRow extends StatefulWidget {
  const _ColorThemeRow({
    required this.title,
    required this.subtitle,
    required this.themeId,
    required this.brightness,
    required this.onSelect,
    required this.showDividerBelow,
  });

  final String title;
  final String subtitle;
  final String themeId;

  /// The slot this row edits; constrains the picker to this brightness.
  final Brightness brightness;
  final ValueChanged<String> onSelect;
  final bool showDividerBelow;

  @override
  State<_ColorThemeRow> createState() => _ColorThemeRowState();
}

class _ColorThemeRowState extends State<_ColorThemeRow> {
  final UserTerminalThemeRegistry _registry =
      UserTerminalThemeRegistry.instance;

  @override
  void initState() {
    super.initState();
    _registry.addListener(_onRegistryChanged);
  }

  @override
  void dispose() {
    _registry.removeListener(_onRegistryChanged);
    super.dispose();
  }

  void _onRegistryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _pick() async {
    final selected = await ColorThemePicker.show(
      context,
      selectedId: widget.themeId,
      brightness: widget.brightness,
      importedThemes: _registry.themes,
    );
    if (selected != null) widget.onSelect(selected);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TpPreferenceRow(
      title: widget.title,
      subtitle: widget.subtitle,
      trailing: TpButton(
        variant: TpButtonVariant.secondary,
        onPressed: _pick,
        child: Text(l10n.colorThemeName(widget.themeId)),
      ),
      showDividerBelow: widget.showDividerBelow,
    );
  }
}
