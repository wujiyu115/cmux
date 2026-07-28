import '../theme/app_theme.dart';
import '../theme/app_typography_scale.dart';
import '../theme/font_catalog.dart';
import '../theme/terminal/terminal_color_slots.dart';

enum LayoutPreset { workbench, chatFocus, inspector }

enum WorkspaceEntryMode { home, lastWorkspace }

/// Default surface when opening a markdown file in the workbench editor.
enum MarkdownOpenMode { preview, source, remember }

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
    this.membersVisible = true,
    this.fileTreeVisible = true,
    this.gitVisible = true,
    this.boardVisible = true,
    this.rightToolsVisible = true,
    this.sidebarVisible = true,
    this.rightToolsWidth = defaultRightToolsWidth,
    this.sidebarWidth = defaultSidebarWidth,
    this.homeSidebarWidth = defaultHomeSidebarWidth,
    this.workspaceNavWidth = defaultWorkspaceNavWidth,
    this.themeMode = 'system',
    this.themeColorPreset = kDefaultThemeColorPreset,
    this.typographyScale = kDefaultTypographyScaleId,
    this.typographyScaleCustomMultiplier = kDefaultTypographyCustomMultiplier,
    this.uiZoomScale = kDefaultTypographyScaleId,
    this.uiZoomCustomMultiplier = kDefaultTypographyCustomMultiplier,
    this.terminalThemeMode = 'adaptive',
    this.useCustomTerminalColors = false,
    this.terminalColorOverrides = const {},
    this.locale = '',
    this.uiFontId = FontCatalog.defaultUiId,
    this.monoFontId = FontCatalog.defaultMonoId,
    this.workspaceTerminalVisible = false,
    this.workspaceTerminalHeight = defaultWorkspaceTerminalHeight,
    this.markdownOpenMode = MarkdownOpenMode.preview,
    this.cotExpandReasoningOnOpen = false,
    this.cotExpandToolsOnOpen = false,
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
      membersVisible: json['membersVisible'] as bool? ?? true,
      fileTreeVisible: json['fileTreeVisible'] as bool? ?? true,
      gitVisible: json['gitVisible'] as bool? ?? true,
      boardVisible: json['boardVisible'] as bool? ?? true,
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
      themeColorPreset: normalizeThemeColorPreset(
        json['themeColorPreset'] as String?,
      ),
      typographyScale: normalizeTypographyScale(
        json['typographyScale'] as String?,
      ),
      typographyScaleCustomMultiplier: clampTypographyCustomMultiplier(
        _doubleValue(
          json['typographyScaleCustomMultiplier'],
          fallback: kDefaultTypographyCustomMultiplier,
        ),
      ),
      uiZoomScale: normalizeTypographyScale(json['uiZoomScale'] as String?),
      uiZoomCustomMultiplier: clampTypographyCustomMultiplier(
        _doubleValue(
          json['uiZoomCustomMultiplier'],
          fallback: kDefaultTypographyCustomMultiplier,
        ),
      ),
      terminalThemeMode: _terminalThemeModeValue(
        json['terminalThemeMode'] as String?,
      ),
      useCustomTerminalColors: json['useCustomTerminalColors'] as bool? ?? false,
      terminalColorOverrides: _terminalColorOverridesFromJson(
        json['terminalColorOverrides'],
      ),
      locale: json['locale'] as String? ?? '',
      uiFontId: normalizeUiFontId(json['uiFontId'] as String?),
      monoFontId: normalizeMonoFontId(json['monoFontId'] as String?),
      workspaceTerminalVisible:
          json['workspaceTerminalVisible'] as bool? ?? false,
      workspaceTerminalHeight: _doubleValue(
        json['workspaceTerminalHeight'],
        fallback: defaultWorkspaceTerminalHeight,
      ).clamp(minWorkspaceTerminalHeight, double.infinity),
      markdownOpenMode:
          _enumValue(MarkdownOpenMode.values, json['markdownOpenMode']) ??
          MarkdownOpenMode.preview,
      cotExpandReasoningOnOpen:
          json['cotExpandReasoningOnOpen'] as bool? ?? false,
      cotExpandToolsOnOpen: json['cotExpandToolsOnOpen'] as bool? ?? false,
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
  final bool membersVisible;
  final bool fileTreeVisible;
  final bool gitVisible;
  final bool boardVisible;
  final bool rightToolsVisible;
  final bool sidebarVisible;
  final double rightToolsWidth;
  final double sidebarWidth;
  final double homeSidebarWidth;
  final double workspaceNavWidth;
  final String themeMode;
  final String themeColorPreset;
  final String typographyScale;
  final double typographyScaleCustomMultiplier;

  /// Whole-UI zoom level (relative preset, independent of text size). The
  /// effective [UiZoom] is the per-display baseline × this preset's multiplier;
  /// `standard` == the auto baseline.
  final String uiZoomScale;
  final double uiZoomCustomMultiplier;
  final String terminalThemeMode;

  /// When true, [terminalColorOverrides] are layered on top of the resolved
  /// terminal theme (see `terminal_theme_mapper.dart`).
  final bool useCustomTerminalColors;

  /// Per-slot custom terminal colours. Keys are `kTerminalColorSlots`; values
  /// are opaque ARGB ints (alpha forced `0xFF` on load). Unknown keys dropped.
  final Map<String, int> terminalColorOverrides;
  final String locale;
  final String uiFontId;
  final String monoFontId;

  /// Legacy bottom-dock flag kept for JSON compat; layout always treats as false.
  final bool workspaceTerminalVisible;
  final double workspaceTerminalHeight;
  final MarkdownOpenMode markdownOpenMode;
  final bool cotExpandReasoningOnOpen;
  final bool cotExpandToolsOnOpen;

  LayoutPreferences copyWith({
    LayoutPreset? preset,
    WorkspaceEntryMode? workspaceEntryMode,
    String? lastOpenedWorkspaceId,
    bool? appRailVisible,
    bool? membersVisible,
    bool? fileTreeVisible,
    bool? gitVisible,
    bool? boardVisible,
    bool? rightToolsVisible,
    bool? sidebarVisible,
    double? rightToolsWidth,
    double? sidebarWidth,
    double? homeSidebarWidth,
    double? workspaceNavWidth,
    String? themeMode,
    String? themeColorPreset,
    String? typographyScale,
    double? typographyScaleCustomMultiplier,
    String? uiZoomScale,
    double? uiZoomCustomMultiplier,
    String? terminalThemeMode,
    bool? useCustomTerminalColors,
    Map<String, int>? terminalColorOverrides,
    String? locale,
    String? uiFontId,
    String? monoFontId,
    bool? workspaceTerminalVisible,
    double? workspaceTerminalHeight,
    MarkdownOpenMode? markdownOpenMode,
    bool? cotExpandReasoningOnOpen,
    bool? cotExpandToolsOnOpen,
  }) {
    return LayoutPreferences(
      preset: preset ?? this.preset,
      workspaceEntryMode: workspaceEntryMode ?? this.workspaceEntryMode,
      lastOpenedWorkspaceId:
          lastOpenedWorkspaceId ?? this.lastOpenedWorkspaceId,
      appRailVisible: appRailVisible ?? this.appRailVisible,
      membersVisible: membersVisible ?? this.membersVisible,
      fileTreeVisible: fileTreeVisible ?? this.fileTreeVisible,
      gitVisible: gitVisible ?? this.gitVisible,
      boardVisible: boardVisible ?? this.boardVisible,
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
      themeColorPreset: themeColorPreset ?? this.themeColorPreset,
      typographyScale: typographyScale == null
          ? this.typographyScale
          : normalizeTypographyScale(typographyScale),
      typographyScaleCustomMultiplier: typographyScaleCustomMultiplier == null
          ? this.typographyScaleCustomMultiplier
          : clampTypographyCustomMultiplier(typographyScaleCustomMultiplier),
      uiZoomScale: uiZoomScale == null
          ? this.uiZoomScale
          : normalizeTypographyScale(uiZoomScale),
      uiZoomCustomMultiplier: uiZoomCustomMultiplier == null
          ? this.uiZoomCustomMultiplier
          : clampTypographyCustomMultiplier(uiZoomCustomMultiplier),
      terminalThemeMode: terminalThemeMode == null
          ? this.terminalThemeMode
          : _terminalThemeModeValue(terminalThemeMode),
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
      workspaceTerminalVisible:
          workspaceTerminalVisible ?? this.workspaceTerminalVisible,
      workspaceTerminalHeight:
          (workspaceTerminalHeight ?? this.workspaceTerminalHeight).clamp(
            minWorkspaceTerminalHeight,
            double.infinity,
          ),
      markdownOpenMode: markdownOpenMode ?? this.markdownOpenMode,
      cotExpandReasoningOnOpen:
          cotExpandReasoningOnOpen ?? this.cotExpandReasoningOnOpen,
      cotExpandToolsOnOpen: cotExpandToolsOnOpen ?? this.cotExpandToolsOnOpen,
    ).withAtLeastOneToolVisible();
  }

  LayoutPreferences withAtLeastOneToolVisible() {
    if (membersVisible || fileTreeVisible) {
      return this;
    }
    return LayoutPreferences(
      preset: preset,
      workspaceEntryMode: workspaceEntryMode,
      lastOpenedWorkspaceId: lastOpenedWorkspaceId,
      appRailVisible: appRailVisible,
      membersVisible: true,
      fileTreeVisible: false,
      gitVisible: gitVisible,
      boardVisible: boardVisible,
      rightToolsVisible: rightToolsVisible,
      sidebarVisible: sidebarVisible,
      rightToolsWidth: rightToolsWidth,
      sidebarWidth: sidebarWidth,
      homeSidebarWidth: homeSidebarWidth,
      workspaceNavWidth: workspaceNavWidth,
      themeMode: themeMode,
      themeColorPreset: themeColorPreset,
      typographyScale: typographyScale,
      typographyScaleCustomMultiplier: typographyScaleCustomMultiplier,
      uiZoomScale: uiZoomScale,
      uiZoomCustomMultiplier: uiZoomCustomMultiplier,
      terminalThemeMode: terminalThemeMode,
      useCustomTerminalColors: useCustomTerminalColors,
      terminalColorOverrides: terminalColorOverrides,
      locale: locale,
      uiFontId: uiFontId,
      monoFontId: monoFontId,
      workspaceTerminalVisible: workspaceTerminalVisible,
      workspaceTerminalHeight: workspaceTerminalHeight,
      markdownOpenMode: markdownOpenMode,
      cotExpandReasoningOnOpen: cotExpandReasoningOnOpen,
      cotExpandToolsOnOpen: cotExpandToolsOnOpen,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'preset': preset.name,
      'workspaceEntryMode': workspaceEntryMode.name,
      'lastOpenedWorkspaceId': lastOpenedWorkspaceId,
      'appRailVisible': appRailVisible,
      'membersVisible': membersVisible,
      'fileTreeVisible': fileTreeVisible,
      'gitVisible': gitVisible,
      'boardVisible': boardVisible,
      'rightToolsVisible': rightToolsVisible,
      'sidebarVisible': sidebarVisible,
      'rightToolsWidth': rightToolsWidth,
      'sidebarWidth': sidebarWidth,
      'homeSidebarWidth': homeSidebarWidth,
      'workspaceNavWidth': workspaceNavWidth,
      'themeMode': themeMode,
      'themeColorPreset': themeColorPreset,
      'typographyScale': typographyScale,
      'typographyScaleCustomMultiplier': typographyScaleCustomMultiplier,
      'uiZoomScale': uiZoomScale,
      'uiZoomCustomMultiplier': uiZoomCustomMultiplier,
      'terminalThemeMode': terminalThemeMode,
      'useCustomTerminalColors': useCustomTerminalColors,
      'terminalColorOverrides': Map<String, int>.from(terminalColorOverrides),
      'locale': locale,
      'uiFontId': uiFontId,
      'monoFontId': monoFontId,
      'workspaceTerminalVisible': workspaceTerminalVisible,
      'workspaceTerminalHeight': workspaceTerminalHeight,
      'markdownOpenMode': markdownOpenMode.name,
      'cotExpandReasoningOnOpen': cotExpandReasoningOnOpen,
      'cotExpandToolsOnOpen': cotExpandToolsOnOpen,
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

String _terminalThemeModeValue(String? raw) {
  if (raw == null || raw.isEmpty) return 'adaptive';
  if (raw == 'adaptive' || raw == 'classicDark' || raw == 'highContrast') {
    return raw;
  }
  // Built-in catalog ids (`dracula`) and user-imported theme ids are both
  // slugs. User themes load *after* preferences at bootstrap, so checking the
  // registry here would clobber a valid imported id; accept any slug and let
  // `terminal_theme_mapper.dart` fall back to adaptive when it resolves to
  // nothing.
  return raw.length <= 64 && _themeSlugPattern.hasMatch(raw)
      ? raw
      : 'adaptive';
}

final RegExp _themeSlugPattern = RegExp(r'^[a-z0-9]+(?:[-_][a-z0-9]+)*$');

WorkspaceEntryMode _workspaceEntryModeFromJson(String? raw) {
  if (raw == 'lastWorkspace') {
    return WorkspaceEntryMode.lastWorkspace;
  }
  // Legacy `hub` and unknown values open home (no redirect shim).
  return WorkspaceEntryMode.home;
}
