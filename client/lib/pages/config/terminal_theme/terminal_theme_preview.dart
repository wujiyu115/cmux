import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';

/// Small terminal-ish preview rendered from the *effective* [TerminalTheme]
/// (scheme + any custom overrides). Purely presentational; reflects live prefs.
class TerminalThemePreview extends StatelessWidget {
  const TerminalThemePreview({required this.theme, super.key});

  final TerminalTheme theme;

  static Color _opaque(int packedRgb) => Color(0xFF000000 | packedRgb);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final background = _opaque(theme.background);
    final foreground = _opaque(theme.foreground);
    final accent = _opaque(theme.hintStart.bg);
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['JetBrains Mono', 'Menlo', 'Consolas'],
      fontSize: 12.5,
      height: 1.5,
      color: foreground,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TpSectionHeader(title: l10n.terminalColorPreviewTitle),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'user@teampilot',
                        style: mono.copyWith(color: accent),
                      ),
                      TextSpan(text: ':~/project ', style: mono),
                      TextSpan(
                        text: r'$ ',
                        style: mono.copyWith(color: _opaque(theme.ansi[2])),
                      ),
                      TextSpan(text: 'git status', style: mono),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text('On branch main', style: mono),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < theme.ansi.length; i++)
                      _AnsiChip(color: _opaque(theme.ansi[i])),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Selection / cursor sample so those slots are visible in the preview.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 14,
                decoration: BoxDecoration(
                  color: _opaque(theme.cursorColor ?? theme.foreground),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _opaque(theme.selection),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text('selection', style: mono.copyWith(fontSize: 11)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _opaque(theme.searchMatch.bg),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  'match',
                  style: styles.mutedSm.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: _opaque(theme.searchMatch.fg),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnsiChip extends StatelessWidget {
  const _AnsiChip({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
      ),
    );
  }
}
