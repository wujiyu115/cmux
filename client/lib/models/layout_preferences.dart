import 'package:flutter/material.dart' show Brightness;

import '../theme/app_theme.dart';
import '../theme/app_typography_scale.dart';
import '../theme/color_theme.dart';
import '../theme/font_catalog.dart';
import '../theme/terminal/terminal_color_slots.dart';
import '../theme/terminal_derived_scheme.dart';

enum LayoutPreset { workbench, chatFocus, inspector }

enum WorkspaceEntryMode { home, lastWorkspace }

/// Default surface when opening a markdown file in the workbench editor.
enum MarkdownOpenMode { preview, source, remember }

/// How the Source Control panel lists changed files.
enum GitChangesViewMode { tree, flat }

/// Dropdown value for language preference: `system` | `en` | `zh`.
String languagePreferenceUiValue(String locale) {
  if (locale.isEmpty) return 'system';
  return locale.startsWith('zh') ? 'zh' : 'en';
}

/// Persisted locale for a language dropdown value (`system` → empty).
String languagePreferenceStoredLocale(String uiValue) {
  return uiValue == 'system' ? '' : uiValue;
}

String normalizeUiFontId(String? id) {
  final raw = id ?? '';
  if (isInstalledFontId(raw)) return raw;
  return FontCatalog.isKnown(FontRole.ui, raw)
      ? raw
      : FontCatalog.defaultUiId;
}

String normalizeMonoFontId(String? id) {
  final raw = id ?? '';
  if (isInstalledFontId(raw)) return raw;
  return FontCatalog.isKnown(FontRole.mono, raw)
      ? raw
      : FontCatalog.defaultMonoId;
}

class LayoutPreferences {
  const LayoutPreferences({
    this.preset = LayoutPreset.workbench,
    this.workspaceEntryMode = WorkspaceEntryMode.home,
    this.lastOpenedWorkspaceId = '',
    this.appRailVisible = true,
    this.fileTreeVisible = true,
    this.gitVisible = true,
    this.rightToolsVisible = true,
    this.sidebarVisible = true,
    this.rightToolsWidth = defaultRightToolsWidth,
    this.sidebarWidth = defaultSidebarWidth,
    this.homeSidebarWidth = defaultHomeSidebarWidth,
    this.workspaceNavWidth = defaultWorkspaceNavWidth,
    this.themeMode = 'system',
    this.lightThemeId = kDefaultLightColorThemeId,
    this.darkThemeId = kDefaultDarkColorThemeId,
    this.uiFontSize = kDefaultUiFontSize,
    this.uiZoomScale = kDefaultUiZoomScaleId,
    this.uiZoomCustomMultiplier = kDefaultUiZoomCustomMultiplier,
    this.useCustomTerminalColors = false,
    this.terminalColorOverrides = const {},
    this.locale = '',
    this.uiFontId = FontCatalog.defaultUiId,
    this.monoFontId = FontCatalog.defaultMonoId,
    this.monoFontSize = kDefaultMonoFontSize,
    this.workspaceTerminalVisible = false,
    this.workspaceTerminalHeight = defaultWorkspaceTerminalHeight,
    this.markdownOpenMode = MarkdownOpenMode.preview,
    this.editorPreviewTabs = true,
    this.gitChangesViewMode = GitChangesViewMode.tree,
  });

  factory LayoutPreferences.fromJson(Map<String, Object?> json) {
    return LayoutPreferences(
      preset:
          _enumValue(LayoutPreset.values, json['preset']) ??
          LayoutPreset.workbench,
      workspaceEntryMode: _workspaceEntryModeFromJson(
        json['workspaceEntryMode'] as String?,
      ),
      lastOpenedWorkspaceId: json['lastOpenedWorkspaceId'] as String? ?? '',
      appRailVisible: json['appRailVisible'] as bool? ?? true,
      fileTreeVisible: json['fileTreeVisible'] as bool? ?? true,
      gitVisible: json['gitVisible'] as bool? ?? true,
      rightToolsVisible: json['rightToolsVisible'] as bool? ?? true,
      sidebarVisible: json['sidebarVisible'] as bool? ?? true,
      rightToolsWidth: _doubleValue(
        json['rightToolsWidth'],
      ).clamp(minRightToolsWidth, double.infinity),
      sidebarWidth: _doubleValue(
        json['sidebarWidth'],
        fallback: defaultSidebarWidth,
      ).clamp(minSidebarWidth, double.infinity),
      homeSidebarWidth: _doubleValue(
        json['homeSidebarWidth'],
        fallback: defaultHomeSidebarWidth,
      ).clamp(minHomeSidebarWidth, double.infinity),
      workspaceNavWidth: _doubleValue(
        json['workspaceNavWidth'],
        fallback: defaultWorkspaceNavWidth,
      ).clamp(minWorkspaceNavWidth, maxWorkspaceNavWidth),
      themeMode: json['themeMode'] as String? ?? 'system',
      lightThemeId: _colorThemeIdFromJson(
        json,
        slot: 'lightThemeId',
        fallback: kDefaultLightColorThemeId,
        brightness: Brightness.light,
      ),
      darkThemeId: _colorThemeIdFromJson(
        json,
        slot: 'darkThemeId',
        fallback: kDefaultDarkColorThemeId,
        brightness: Brightness.dark,
      ),
      uiFontSize: _uiFontSizeFromJson(json),
      uiZoomScale: normalizeUiZoomScale(json['uiZoomScale'] as String?),
      uiZoomCustomMultiplier: clampUiZoomCustomMultiplier(
        _doubleValue(
          json['uiZoomCustomMultiplier'],
          fallback: kDefaultUiZoomCustomMultiplier,
        ),
      ),
      useCustomTerminalColors: json['useCustomTerminalColors'] as bool? ?? false,
      terminalColorOverrides: _terminalColorOverridesFromJson(
        json['terminalColorOverrides'],
      ),
      locale: json['locale'] as String? ?? '',
      uiFontId: normalizeUiFontId(json['uiFontId'] as String?),
      monoFontId: normalizeMonoFontId(json['monoFontId'] as String?),
      monoFontSize: _monoFontSizeFromJson(json),
      workspaceTerminalVisible:
          json['workspaceTerminalVisible'] as bool? ?? false,
      workspaceTerminalHeight: _doubleValue(
        json['workspaceTerminalHeight'],
        fallback: defaultWorkspaceTerminalHeight,
      ).clamp(minWorkspaceTerminalHeight, double.infinity),
      markdownOpenMode:
          _enumValue(MarkdownOpenMode.values, json['markdownOpenMode']) ??
          MarkdownOpenMode.preview,
      editorPreviewTabs: json['editorPreviewTabs'] as bool? ?? true,
      gitChangesViewMode:
          _enumValue(GitChangesViewMode.values, json['gitChangesViewMode']) ??
          GitChangesViewMode.tree,
    ).withAtLeastOneToolVisible();
  }

  static const defaultRightToolsWidth = 320.0;
  static const minRightToolsWidth = 240.0;
  static const defaultSidebarWidth = 260.0;
  static const minSidebarWidth = 180.0;
  static const defaultHomeSidebarWidth = 420.0;
  static const minHomeSidebarWidth = 280.0;
  static const defaultWorkspaceNavWidth = 220.0;
  static const minWorkspaceNavWidth = 200.0;
  static const maxWorkspaceNavWidth = 360.0;
  static const defaultWorkspaceTerminalHeight = 220.0;
  static const minWorkspaceTerminalHeight = 120.0;

  /// Minimum extent for the main workbench column beside a side panel.
  static const minWorkbenchMainWidth = 320.0;

  /// Minimum extent for the main workbench row above the bottom terminal.
  static const minWorkbenchMainHeight = 200.0;

  /// Minimum LLM provider detail column in the config split.
  static const minLlmProviderDetailWidth = 280.0;

  /// Minimum settings hub content column beside nav.
  static const minWorkspaceHubContentWidth = 480.0;

  final LayoutPreset preset;
  final WorkspaceEntryMode workspaceEntryMode;
  final String lastOpenedWorkspaceId;
  final bool appRailVisible;
  final bool fileTreeVisible;
  final bool gitVisible;
  final bool rightToolsVisible;
  final bool sidebarVisible;
  final double rightToolsWidth;
  final double sidebarWidth;
  final double homeSidebarWidth;
  final double workspaceNavWidth;
  final String themeMode;

  /// Active colour theme per brightness slot (VS Code
  /// `preferredLight/DarkColorTheme`). Each id names the whole-app look — see
  /// `color_theme.dart`; [themeMode] picks the slot, or follows the platform.
  final String lightThemeId;
  final String darkThemeId;
  /// UI body text size in logical px; every UI role derives from it via
  /// [AppTypographyScale.fromPx]. See [clampUiFontSize] for the range.
  final double uiFontSize;

  /// Whole-UI zoom level (relative preset, independent of font sizes). The
  /// effective [UiZoom] renders at this preset's multiplier; `standard` ==
  /// 1.0 (100%). The OS display scaling is handled natively by Flutter and
  /// is NOT compensated here (see docs/font-size-model.md §5).
  final String uiZoomScale;
  final double uiZoomCustomMultiplier;

  /// When true, [terminalColorOverrides] are layered on top of the resolved
  /// terminal theme (see `terminal_theme_mapper.dart`).
  final bool useCustomTerminalColors;

  /// Per-slot custom terminal colours. Keys are `kTerminalColorSlots`; values
  /// are opaque ARGB ints (alpha forced `0xFF` on load). Unknown keys dropped.
  final Map<String, int> terminalColorOverrides;
  final String locale;
  final String uiFontId;
  final String monoFontId;

  /// Monospace size (terminal + editor + diffs) in logical px; see
  /// [clampMonoFontSize] for the range.
  final double monoFontSize;

  /// Legacy bottom-dock flag kept for JSON compat; layout always treats as false.
  final bool workspaceTerminalVisible;
  final double workspaceTerminalHeight;
  final MarkdownOpenMode markdownOpenMode;

  /// Whether single-click opens reuse the shared preview tab slot. When false
  /// every open pins its own tab (VSCode `enablePreview: false`).
  final bool editorPreviewTabs;

  /// Tree (collapsible folders) vs flat (full relative paths) listing in the
  /// Source Control panel.
  final GitChangesViewMode gitChangesViewMode;

  LayoutPreferences copyWith({
    LayoutPreset? preset,
    WorkspaceEntryMode? workspaceEntryMode,
    String? lastOpenedWorkspaceId,
    bool? appRailVisible,
    bool? fileTreeVisible,
    bool? gitVisible,
    bool? rightToolsVisible,
    bool? sidebarVisible,
    double? rightToolsWidth,
    double? sidebarWidth,
    double? homeSidebarWidth,
    double? workspaceNavWidth,
    String? themeMode,
    String? lightThemeId,
    String? darkThemeId,
    double? uiFontSize,
    String? uiZoomScale,
    double? uiZoomCustomMultiplier,
    bool? useCustomTerminalColors,
    Map<String, int>? terminalColorOverrides,
    String? locale,
    String? uiFontId,
    String? monoFontId,
    double? monoFontSize,
    bool? workspaceTerminalVisible,
    double? workspaceTerminalHeight,
    MarkdownOpenMode? markdownOpenMode,
    bool? editorPreviewTabs,
    GitChangesViewMode? gitChangesViewMode,
  }) {
    return LayoutPreferences(
      preset: preset ?? this.preset,
      workspaceEntryMode: workspaceEntryMode ?? this.workspaceEntryMode,
      lastOpenedWorkspaceId:
          lastOpenedWorkspaceId ?? this.lastOpenedWorkspaceId,
      appRailVisible: appRailVisible ?? this.appRailVisible,
      fileTreeVisible: fileTreeVisible ?? this.fileTreeVisible,
      gitVisible: gitVisible ?? this.gitVisible,
      rightToolsVisible: rightToolsVisible ?? this.rightToolsVisible,
      sidebarVisible: sidebarVisible ?? this.sidebarVisible,
      rightToolsWidth: (rightToolsWidth ?? this.rightToolsWidth).clamp(
        minRightToolsWidth,
        double.infinity,
      ),
      sidebarWidth: (sidebarWidth ?? this.sidebarWidth).clamp(
        minSidebarWidth,
        double.infinity,
      ),
      homeSidebarWidth: (homeSidebarWidth ?? this.homeSidebarWidth).clamp(
        minHomeSidebarWidth,
        double.infinity,
      ),
      workspaceNavWidth: (workspaceNavWidth ?? this.workspaceNavWidth).clamp(
        minWorkspaceNavWidth,
        maxWorkspaceNavWidth,
      ),
      themeMode: themeMode ?? this.themeMode,
      lightThemeId: coerceColorThemeBrightness(
        normalizeColorThemeId(lightThemeId, this.lightThemeId),
        Brightness.light,
        kDefaultLightColorThemeId,
      ),
      darkThemeId: coerceColorThemeBrightness(
        normalizeColorThemeId(darkThemeId, this.darkThemeId),
        Brightness.dark,
        kDefaultDarkColorThemeId,
      ),
      uiFontSize: uiFontSize == null
          ? this.uiFontSize
          : clampUiFontSize(uiFontSize),
      uiZoomScale: uiZoomScale == null
          ? this.uiZoomScale
          : normalizeUiZoomScale(uiZoomScale),
      uiZoomCustomMultiplier: uiZoomCustomMultiplier == null
          ? this.uiZoomCustomMultiplier
          : clampUiZoomCustomMultiplier(uiZoomCustomMultiplier),
      useCustomTerminalColors:
          useCustomTerminalColors ?? this.useCustomTerminalColors,
      terminalColorOverrides: terminalColorOverrides == null
          ? this.terminalColorOverrides
          : _sanitizeTerminalColorOverrides(terminalColorOverrides),
      locale: locale ?? this.locale,
      uiFontId: uiFontId == null ? this.uiFontId : normalizeUiFontId(uiFontId),
      monoFontId: monoFontId == null
          ? this.monoFontId
          : normalizeMonoFontId(monoFontId),
      monoFontSize: monoFontSize == null
          ? this.monoFontSize
          : clampMonoFontSize(monoFontSize),
      workspaceTerminalVisible:
          workspaceTerminalVisible ?? this.workspaceTerminalVisible,
      workspaceTerminalHeight:
          (workspaceTerminalHeight ?? this.workspaceTerminalHeight).clamp(
            minWorkspaceTerminalHeight,
            double.infinity,
          ),
      markdownOpenMode: markdownOpenMode ?? this.markdownOpenMode,
      editorPreviewTabs: editorPreviewTabs ?? this.editorPreviewTabs,
      gitChangesViewMode: gitChangesViewMode ?? this.gitChangesViewMode,
    ).withAtLeastOneToolVisible();
  }

  LayoutPreferences withAtLeastOneToolVisible() {
    if (fileTreeVisible) return this;
    return LayoutPreferences(
      preset: preset,
      workspaceEntryMode: workspaceEntryMode,
      lastOpenedWorkspaceId: lastOpenedWorkspaceId,
      appRailVisible: appRailVisible,
      fileTreeVisible: true,
      gitVisible: gitVisible,
      rightToolsVisible: rightToolsVisible,
      sidebarVisible: sidebarVisible,
      rightToolsWidth: rightToolsWidth,
      sidebarWidth: sidebarWidth,
      homeSidebarWidth: homeSidebarWidth,
      workspaceNavWidth: workspaceNavWidth,
      themeMode: themeMode,
      lightThemeId: lightThemeId,
      darkThemeId: darkThemeId,
      uiFontSize: uiFontSize,
      uiZoomScale: uiZoomScale,
      uiZoomCustomMultiplier: uiZoomCustomMultiplier,
      useCustomTerminalColors: useCustomTerminalColors,
      terminalColorOverrides: terminalColorOverrides,
      locale: locale,
      uiFontId: uiFontId,
      monoFontId: monoFontId,
      monoFontSize: monoFontSize,
      workspaceTerminalVisible: workspaceTerminalVisible,
      workspaceTerminalHeight: workspaceTerminalHeight,
      markdownOpenMode: markdownOpenMode,
      editorPreviewTabs: editorPreviewTabs,
      gitChangesViewMode: gitChangesViewMode,
    );
  }

  /// Resolves the active colour theme for the current platform brightness:
  /// the theme id, the brightness it actually renders at (a terminal theme
  /// carries its own — a dark theme in the light slot still renders dark),
  /// and the terminal mode the theme mapper consumes.
  ({String themeId, Brightness brightness, String terminalMode})
  resolveColorTheme({required bool platformDark}) {
    final themeId = switch (themeMode) {
      'light' => lightThemeId,
      'dark' => darkThemeId,
      _ => platformDark ? darkThemeId : lightThemeId,
    };
    return (
      themeId: themeId,
      brightness: colorThemeBrightness(themeId),
      terminalMode: terminalModeForColorTheme(themeId),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'preset': preset.name,
      'workspaceEntryMode': workspaceEntryMode.name,
      'lastOpenedWorkspaceId': lastOpenedWorkspaceId,
      'appRailVisible': appRailVisible,
      'fileTreeVisible': fileTreeVisible,
      'gitVisible': gitVisible,
      'rightToolsVisible': rightToolsVisible,
      'sidebarVisible': sidebarVisible,
      'rightToolsWidth': rightToolsWidth,
      'sidebarWidth': sidebarWidth,
      'homeSidebarWidth': homeSidebarWidth,
      'workspaceNavWidth': workspaceNavWidth,
      'themeMode': themeMode,
      'lightThemeId': lightThemeId,
      'darkThemeId': darkThemeId,
      'uiFontSize': uiFontSize,
      'uiZoomScale': uiZoomScale,
      'uiZoomCustomMultiplier': uiZoomCustomMultiplier,
      'useCustomTerminalColors': useCustomTerminalColors,
      'terminalColorOverrides': Map<String, int>.from(terminalColorOverrides),
      'locale': locale,
      'uiFontId': uiFontId,
      'monoFontId': monoFontId,
      'monoFontSize': monoFontSize,
      'workspaceTerminalVisible': workspaceTerminalVisible,
      'workspaceTerminalHeight': workspaceTerminalHeight,
      'markdownOpenMode': markdownOpenMode.name,
      'editorPreviewTabs': editorPreviewTabs,
      'gitChangesViewMode': gitChangesViewMode.name,
    };
  }
}

T? _enumValue<T extends Enum>(List<T> values, Object? raw) {
  if (raw is! String) {
    return null;
  }
  for (final value in values) {
    if (value.name == raw) {
      return value;
    }
  }
  return null;
}

double _doubleValue(Object? raw, {double fallback = 320.0}) {
  if (raw is num) {
    return raw.toDouble();
  }
  return fallback;
}

/// Sanitizes a raw override map: drops unknown slot keys and non-int values,
/// then forces each colour opaque (alpha `0xFF`). Returned map is unmodifiable.
Map<String, int> _sanitizeTerminalColorOverrides(Map<String, int> raw) {
  final out = <String, int>{};
  for (final entry in raw.entries) {
    if (!isTerminalColorSlot(entry.key)) continue;
    out[entry.key] = normalizeTerminalColorValue(entry.value);
  }
  return Map<String, int>.unmodifiable(out);
}

/// [fromJson] variant tolerant of arbitrary JSON shapes (num values, non-string
/// keys, non-map input) so a hand-edited prefs file can't poison rendering.
Map<String, int> _terminalColorOverridesFromJson(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, int>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is! String || !isTerminalColorSlot(key)) continue;
    final value = entry.value;
    final intValue = value is int
        ? value
        : (value is num ? value.toInt() : null);
    if (intValue == null) continue;
    out[key] = normalizeTerminalColorValue(intValue);
  }
  return Map<String, int>.unmodifiable(out);
}

/// Migrates the legacy `themeColorPreset` + `terminalThemeMode` pair into a
/// per-brightness colour-theme id. The new [slot] key wins when present (and
/// is coerced to the slot's brightness); otherwise the two old fields are
/// split by brightness:
///
/// - a terminal theme (`terminalThemeMode != 'adaptive'`) fills **only the slot
///   matching its own brightness**; the other slot keeps the legacy preset at
///   that slot's brightness (or the default when the preset was `terminal`);
/// - a fixed UI preset (`themeColorPreset != 'terminal'`) fills each slot as
///   `ui:{preset}:{light|dark}`, matching the old behaviour where one preset
///   rendered both light and dark;
/// - the degenerate `terminal` + `adaptive` fallback → the slot default.
///
/// See docs/theme-model.md §4.
String _colorThemeIdFromJson(
  Map<String, Object?> json, {
  required String slot,
  required String fallback,
  required Brightness brightness,
}) {
  final raw = json[slot];
  if (raw is String && raw.isNotEmpty) {
    return coerceColorThemeBrightness(
      normalizeColorThemeId(raw, fallback),
      brightness,
      fallback,
    );
  }
  final legacyMode = json['terminalThemeMode'] as String?;
  final legacyPreset = normalizeThemeColorPreset(
    json['themeColorPreset'] as String?,
  );
  if (legacyMode != null && legacyMode.isNotEmpty && legacyMode != 'adaptive') {
    final mode = normalizeColorThemeId(legacyMode, fallback);
    if (colorThemeBrightness(mode) == brightness) return mode;
    // Wrong-brightness slot keeps the legacy preset at its own brightness.
    return legacyPreset == kTerminalDerivedPresetId
        ? fallback
        : uiColorThemeId(legacyPreset, brightness);
  }
  if (legacyPreset != kTerminalDerivedPresetId) {
    return uiColorThemeId(legacyPreset, brightness);
  }
  return fallback;
}

WorkspaceEntryMode _workspaceEntryModeFromJson(String? raw) {
  if (raw == 'lastWorkspace') {
    return WorkspaceEntryMode.lastWorkspace;
  }
  // Legacy `hub` and unknown values open home (no redirect shim).
  return WorkspaceEntryMode.home;
}

/// Legacy relative text-size preset multiplier (compact 0.92 / standard 1.0 /
/// comfortable 1.08 / custom = stored multiplier), used only by the px
/// migration below. See docs/font-size-model.md §5.
double _legacyTextMultiplier(Map<String, Object?> json) {
  final scaleId = json['typographyScale'] as String?;
  if (scaleId == 'custom') {
    final m = _doubleValue(
      json['typographyScaleCustomMultiplier'],
      fallback: 1.0,
    );
    return m.clamp(0.5, 2.0);
  }
  return switch (scaleId) {
    'compact' => 0.92,
    'comfortable' => 1.08,
    _ => 1.0,
  };
}

/// `uiFontSize` migration: new field wins; otherwise fold the legacy
/// 「文字大小」 preset into px (`round(14 × p)`). The zoom baseline flip
/// (1/dpr → 1.0) cancels the old OS text baseline, so this static mapping is
/// visually unchanged at any dpr.
double _uiFontSizeFromJson(Map<String, Object?> json) {
  final raw = json['uiFontSize'];
  if (raw is num) return clampUiFontSize(raw.toDouble());
  return clampUiFontSize((kUiFontSizeBase * _legacyTextMultiplier(json)).roundToDouble());
}

/// `monoFontSize` migration: new field wins; otherwise fold the legacy
/// 「等宽字号」 multiplier into px — today's logical mono size is
/// `14 × p × s`, so the migration must include the text preset `p` (the
/// original design draft's mono table omitted it).
double _monoFontSizeFromJson(Map<String, Object?> json) {
  final raw = json['monoFontSize'];
  if (raw is num) return clampMonoFontSize(raw.toDouble());
  final s = _doubleValue(json['monoFontScale'], fallback: 1.0).clamp(0.7, 1.6);
  final p = _legacyTextMultiplier(json);
  return clampMonoFontSize((kUiFontSizeBase * p * s).roundToDouble());
}
