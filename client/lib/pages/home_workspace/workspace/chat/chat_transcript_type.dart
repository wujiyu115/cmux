import 'package:flutter/material.dart';

import '../../../../theme/app_fonts.dart';
import '../../../../theme/app_typography_scale.dart';

/// Text roles for a rendered conversation, sized like the terminal grid.
///
/// A chat pane replaces a terminal grid in the same box, so it has to read at
/// the same scale: `设置 → 外观 → 等宽字号` (`LayoutPreferences.monoFontSize`)
/// drives `AppTypographyTheme.terminal`, which is what the grid uses. Sizing
/// the conversation from the UI scale instead made a 10px terminal sit next to
/// 13px prose in the same pane.
///
/// Family is the mono face too — the transcript carries commands, tool output
/// and file paths, and on mobile a bare `'monospace'` family resolves to a
/// fontconfig generic that iOS cannot load (same trap the mirror terminal hit).
@immutable
class ChatTranscriptType {
  const ChatTranscriptType._({
    required this.body,
    required this.meta,
    required this.tool,
  });

  /// Assistant prose, a user's prompt, a tool header.
  final TextStyle body;

  /// Labels, notices, hints, thinking rows: one step below [body].
  final TextStyle meta;

  /// Tool output and other verbatim blocks.
  final TextStyle tool;

  factory ChatTranscriptType.of(BuildContext context) {
    final size = context.appTypography.terminal;
    final body = appMonoTextStyle(context, fontSize: size, height: 1.45);
    final meta = body.copyWith(fontSize: size * 0.86, height: 1.4);
    return ChatTranscriptType._(
      body: body,
      meta: meta,
      tool: meta.copyWith(height: 1.35),
    );
  }

  /// Body text in [color].
  TextStyle bodyIn(Color color) => body.copyWith(color: color);

  /// Secondary text in [color].
  TextStyle metaIn(Color color) => meta.copyWith(color: color);

  /// Verbatim text in [color].
  TextStyle toolIn(Color color) => tool.copyWith(color: color);
}
