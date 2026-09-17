import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Central **font size** configuration for TeamPilot UI.
///
/// Font sizes are absolute logical px, mirroring VS Code's `editor.fontSize`
/// / `terminal.integrated.fontSize` model: [LayoutPreferences.uiFontSize] and
/// [LayoutPreferences.monoFontSize] feed [AppTypographyScale.fromPx], and the
/// whole-UI zoom (`uiZoomScale`) is the only remaining relative knob. The OS
/// display scaling (devicePixelRatio) is handled natively by Flutter — the app
/// no longer compensates for it in text sizes.
///
/// Edit base values here (or pass another scale when building [ThemeData]) —
/// widgets read sizes via [TextTheme] / [TpTextStyles], not these constants
/// directly.
///
/// Exceptions: terminal [TerminalStyle] uses [terminal]; see `chat_workbench.dart`.

// --- Font sizes (absolute logical px) ---

/// UI body text size (`bodyMedium` baseline); every other UI role derives as
/// `roleBase × (uiFontSize / kUiFontSizeBase)`.
const double kUiFontSizeBase = 14;
const double kUiFontSizeMin = 10;
const double kUiFontSizeMax = 28;
const double kDefaultUiFontSize = 14;

double clampUiFontSize(double value) => value.clamp(kUiFontSizeMin, kUiFontSizeMax);

/// Monospace faces (terminal + code editor + diffs), absolute px like VS
/// Code's `terminal.integrated.fontSize`.
const double kMonoFontSizeMin = 8;
const double kMonoFontSizeMax = 28;
const double kDefaultMonoFontSize = 14;

double clampMonoFontSize(double value) => value.clamp(kMonoFontSizeMin, kMonoFontSizeMax);

// --- Whole-UI zoom (relative presets) ---

/// Persisted zoom preset ids (settings UI order). These are **relative**
/// levels applied to the whole UI via [UiZoom]: `standard` (×1.0) renders at
/// 100%, `compact` is a bit tighter, `comfortable` a bit looser, `custom` a %
/// of standard.
const List<String> kUiZoomScaleIds = ['compact', 'standard', 'comfortable', 'custom'];

const String kDefaultUiZoomScaleId = 'standard';

/// Allowed custom zoom multiplier (× standard).
const double kUiZoomCustomMultiplierMin = 0.5;
const double kUiZoomCustomMultiplierMax = 2.0;
const double kDefaultUiZoomCustomMultiplier = 1.0;

double clampUiZoomCustomMultiplier(double value) =>
    value.clamp(kUiZoomCustomMultiplierMin, kUiZoomCustomMultiplierMax);

String normalizeUiZoomScale(String? raw) {
  if (raw != null && kUiZoomScaleIds.contains(raw)) return raw;
  return kDefaultUiZoomScaleId;
}

/// Final-effective **interface zoom** clamp (whole-UI [UiZoom]).
const double kUiZoomMin = 0.5;
const double kUiZoomMax = 1.5;

double clampUiZoom(double value) => value.clamp(kUiZoomMin, kUiZoomMax);

/// Fixed step applied per press by the `workbench.zoom.in`/`.out` commands.
const double kUiZoomStep = 0.1;

/// Preset multipliers for the zoom segments.
const double kUiZoomCompactMultiplier = 0.92;
const double kUiZoomComfortableMultiplier = 1.08;

/// Resolves the stored zoom preference (`scaleId` + `customMultiplier`) to the
/// multiplier [UiZoom] renders with (still subject to [clampUiZoom]).
double uiZoomMultiplierFor({
  required String scaleId,
  required double customMultiplier,
}) {
  if (normalizeUiZoomScale(scaleId) == 'custom') {
    return clampUiZoomCustomMultiplier(customMultiplier);
  }
  return switch (normalizeUiZoomScale(scaleId)) {
    'compact' => kUiZoomCompactMultiplier,
    'comfortable' => kUiZoomComfortableMultiplier,
    _ => 1.0,
  };
}

@immutable
final class AppTypographyScale {
  const AppTypographyScale({this.multiplier = 1.0, this.monoPx});

  /// Builds the scale from the persisted absolute px preferences: UI roles
  /// derive from [uiFontSize] (14 px = design baseline), mono faces render at
  /// exactly [monoFontSize] px.
  factory AppTypographyScale.fromPx({
    required double uiFontSize,
    required double monoFontSize,
  }) {
    return AppTypographyScale(
      multiplier: uiFontSize / kUiFontSizeBase,
      monoPx: monoFontSize,
    );
  }

  /// Default scale used by [buildLightTheme] / [buildDarkTheme].
  static const standard = AppTypographyScale();

  /// Slightly denser UI (≈ −8%); a convenience fixture for tests/derivations.
  static const compact = AppTypographyScale(
    multiplier: kUiZoomCompactMultiplier,
  );

  /// Slightly roomier UI (≈ +8%); a convenience fixture for tests/derivations.
  static const comfortable = AppTypographyScale(
    multiplier: kUiZoomComfortableMultiplier,
  );

  /// Applied to every UI role below (also composes with [MediaQuery.textScaler]).
  final double multiplier;

  /// Absolute monospace size (terminal / editor / diffs) in logical px. When
  /// null, mono derives from [multiplier] (legacy warmup / fallback paths).
  final double? monoPx;

  // --- Base sizes at multiplier 1.0 (Material 3 type scale) ---

  static const double headlineSmallBase = 24;
  static const double titleLargeBase = 20;
  static const double titleMediumBase = 16;
  static const double titleSmallBase = 14;
  static const double bodyLargeBase = 16;
  static const double bodyMediumBase = 14;
  static const double bodySmallBase = 12;

  /// Button labels ([TextButton]/[OutlinedButton]/[FilledButton] use M3
  /// `labelLarge`).
  static const double labelLargeBase = 14;
  static const double labelMediumBase = 12;
  static const double labelSmallBase = 11;

  /// xterm / bundled terminal face (not [TextTheme]).
  static const double terminalBase = 14;

  /// Code editor & log viewer monospace (defaults to body medium).
  static const double monoBase = bodyMediumBase;

  double get headlineSmall => headlineSmallBase * multiplier;
  double get titleLarge => titleLargeBase * multiplier;
  double get titleMedium => titleMediumBase * multiplier;
  double get titleSmall => titleSmallBase * multiplier;
  double get bodyLarge => bodyLargeBase * multiplier;
  double get bodyMedium => bodyMediumBase * multiplier;
  double get bodySmall => bodySmallBase * multiplier;
  double get labelLarge => labelLargeBase * multiplier;
  double get labelMedium => labelMediumBase * multiplier;
  double get labelSmall => labelSmallBase * multiplier;
  double get terminal => monoPx ?? terminalBase * multiplier;
  double get mono => monoPx ?? monoBase * multiplier;
}

/// Resolved sizes on [ThemeData.extensions] (from [AppTypographyScale]).
@immutable
final class AppTypographyTheme extends ThemeExtension<AppTypographyTheme> {
  const AppTypographyTheme({
    required this.headlineSmall,
    required this.titleLarge,
    required this.titleMedium,
    required this.titleSmall,
    required this.bodyLarge,
    required this.bodyMedium,
    required this.bodySmall,
    required this.labelMedium,
    required this.labelSmall,
    required this.mono,
    required this.terminal,
  });

  final double headlineSmall;
  final double titleLarge;
  final double titleMedium;
  final double titleSmall;
  final double bodyLarge;
  final double bodyMedium;
  final double bodySmall;
  final double labelMedium;
  final double labelSmall;
  final double mono;
  final double terminal;

  factory AppTypographyTheme.fromScale(AppTypographyScale scale) {
    return AppTypographyTheme(
      headlineSmall: scale.headlineSmall,
      titleLarge: scale.titleLarge,
      titleMedium: scale.titleMedium,
      titleSmall: scale.titleSmall,
      bodyLarge: scale.bodyLarge,
      bodyMedium: scale.bodyMedium,
      bodySmall: scale.bodySmall,
      labelMedium: scale.labelMedium,
      labelSmall: scale.labelSmall,
      mono: scale.mono,
      terminal: scale.terminal,
    );
  }

  static AppTypographyTheme fromContext(BuildContext context) =>
      Theme.of(context).extension<AppTypographyTheme>() ??
      AppTypographyTheme.fromScale(AppTypographyScale.standard);

  @override
  AppTypographyTheme copyWith({
    double? headlineSmall,
    double? titleLarge,
    double? titleMedium,
    double? titleSmall,
    double? bodyLarge,
    double? bodyMedium,
    double? bodySmall,
    double? labelMedium,
    double? labelSmall,
    double? mono,
    double? terminal,
  }) {
    return AppTypographyTheme(
      headlineSmall: headlineSmall ?? this.headlineSmall,
      titleLarge: titleLarge ?? this.titleLarge,
      titleMedium: titleMedium ?? this.titleMedium,
      titleSmall: titleSmall ?? this.titleSmall,
      bodyLarge: bodyLarge ?? this.bodyLarge,
      bodyMedium: bodyMedium ?? this.bodyMedium,
      bodySmall: bodySmall ?? this.bodySmall,
      labelMedium: labelMedium ?? this.labelMedium,
      labelSmall: labelSmall ?? this.labelSmall,
      mono: mono ?? this.mono,
      terminal: terminal ?? this.terminal,
    );
  }

  @override
  AppTypographyTheme lerp(ThemeExtension<AppTypographyTheme>? other, double t) {
    if (other is! AppTypographyTheme) return this;
    return t < 0.5 ? this : other;
  }
}

extension AppTypographyThemeContext on BuildContext {
  AppTypographyTheme get appTypography => AppTypographyTheme.fromContext(this);
}
