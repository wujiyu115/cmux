import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:shared_ui/shared_ui.dart';

/// Text styles [buildAppCompiledMarkdownStyle] paints — boot glyph warmup.
List<TextStyle> appMarkdownTextStyles(ThemeData theme) {
  return buildAppCompiledMarkdownStyle(theme).textStylesForWarmup;
}

/// CJK-safe line height for markdown text. The bundled Noto Sans SC measures
/// ~1.43–1.46em natural ascent+descent, so the design system's 1.25/1.35
/// multipliers compress line boxes below the glyph metrics and Chinese text
/// overlaps line to line. 1.5 keeps every markdown style above the natural
/// metrics of the CJK fonts in the fallback chains.
const double _markdownLineHeight = 1.5;

/// Host [CompiledMarkdownStyle] bound to [TpTextStyles] + [TpFontTheme].
///
/// Uses only warmup-covered size/weight variants — no ad-hoc sizes that miss
/// the glyph cache. Install on [AiMessageTheme.markdown].
CompiledMarkdownStyle buildAppCompiledMarkdownStyle(
  ThemeData theme, {
  Color? mutedSurface,
  double codeBlockRadius = 12,
}) {
  final fonts = theme.extension<TpFontTheme>() ?? TpFontTheme.fallback;
  final styles = TpTextStyles(theme);
  final scheme = theme.colorScheme;

  TextStyle withUi(TextStyle style) => style.copyWith(
    fontFamily: fonts.uiFontFamily,
    fontFamilyFallback: fonts.uiFontFamilyFallback,
    height: _markdownLineHeight,
  );

  final body = withUi(styles.md);
  final muted = mutedSurface ??
      scheme.surfaceContainerHighest.withValues(alpha: 0.55);
  final inlineCode = body.copyWith(
    fontFamily: fonts.monoFontFamily,
    fontFamilyFallback: fonts.monoFontFamilyFallback,
    backgroundColor: muted.withValues(alpha: 0.55),
  );
  final codeBlock = styles.mono.copyWith(
    color: scheme.onSurface,
    height: _markdownLineHeight,
  );

  return CompiledMarkdownStyle(
    body: body,
    // Size ladder (Material text theme): display → xl → lg → md.
    // Prefer warmup-covered TpTextStyles tokens over ad-hoc fontSize.
    h1: withUi(styles.display),
    h2: withUi(styles.xl),
    h3: withUi(styles.lgSemiboldSnug),
    h4: withUi(styles.lgSnug),
    h5: withUi(styles.mdSemiboldTightSnug),
    h6: body,
    link: body.copyWith(
      color: scheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: scheme.primary,
    ),
    inlineCode: inlineCode,
    codeBlock: codeBlock,
    codeLanguage: withUi(styles.mutedSm),
    listBullet: body,
    blockquote: withUi(styles.mutedMd),
    tableHead: withUi(styles.mdSemibold),
    tableBody: body,
    mutedSurface: muted,
    borderColor: scheme.outlineVariant.withValues(alpha: 0.55),
    codeBlockRadius: codeBlockRadius,
  );
}

/// [MarkdownBody] / file-preview sheet derived from the compiled host styles.
MarkdownStyleSheet buildAppMarkdownStyleSheet(ThemeData theme) {
  return buildAppCompiledMarkdownStyle(theme).toMarkdownStyleSheet();
}

/// Default [AiMessageTheme] for the app shell; chat routes override layout tokens.
AiMessageTheme buildAppAiMessageTheme(ThemeData theme) {
  return AiMessageTheme(
    markdown: buildAppCompiledMarkdownStyle(theme),
  );
}
