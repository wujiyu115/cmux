import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../services/theme/terminal_theme_import.dart';

/// Paste-or-pick dialog for importing an Alacritty / Ghostty colour scheme.
///
/// Parsing happens here so a bad file shows an inline error without closing the
/// dialog; the caller only ever receives a successfully parsed theme. Returns
/// null when dismissed.
Future<TerminalThemeImportResult?> showTerminalThemeImportDialog(
  BuildContext context,
) {
  return showDialog<TerminalThemeImportResult>(
    context: context,
    builder: (_) => const _TerminalThemeImportDialog(),
  );
}

class _TerminalThemeImportDialog extends StatefulWidget {
  const _TerminalThemeImportDialog();

  @override
  State<_TerminalThemeImportDialog> createState() =>
      _TerminalThemeImportDialogState();
}

class _TerminalThemeImportDialogState
    extends State<_TerminalThemeImportDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _source = TextEditingController();

  /// Inline error, already localized (an l10n string, not an import code).
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;

    return TpDialog(
      maxWidth: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(
            title: l10n.terminalThemeImportTitle,
            onClose: () => Navigator.of(context).pop(),
          ),
          // Scrolls on short windows so the paste area never overflows the
          // dialog (which would clip the actions row).
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    l10n.terminalThemeImportDescription,
                    style: styles.mutedSm,
                  ),
                  const SizedBox(height: 16),
                  TpInput(
                    key: const Key('terminal-theme-import-name'),
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: l10n.terminalThemeImportNameLabel,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(l10n.terminalThemeImportSourceLabel),
                      ),
                      TpButton(
                        variant: TpButtonVariant.ghost,
                        onPressed: _pickFile,
                        child: Text(l10n.terminalThemeImportChooseFile),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TpTextarea(
                    key: const Key('terminal-theme-import-source'),
                    controller: _source,
                    minHeight: tpTextareaHeightForLines(styles.md, lines: 8),
                    maxHeight: tpTextareaHeightForLines(styles.md, lines: 8),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: styles.mutedSm.copyWith(color: cs.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
          TpDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                key: const Key('terminal-theme-import-confirm'),
                onPressed: _submit,
                child: Text(l10n.terminalThemeImportConfirm),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Loads a file into the text area (rather than importing straight away) so
  /// the parse path and the error surface stay identical for both entry points.
  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles();
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.first.path;
    if (path == null || !mounted) return;
    final l10n = context.l10n;
    try {
      final contents = await File(path).readAsString();
      if (!mounted) return;
      setState(() {
        _source.text = contents;
        _error = null;
        if (_name.text.trim().isEmpty) {
          _name.text = _themeNameFromPath(path);
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() => _error = l10n.terminalThemeImportFileReadFailed);
    }
  }

  void _submit() {
    final l10n = context.l10n;
    final source = _source.text;
    if (source.trim().isEmpty) {
      setState(() => _error = l10n.terminalThemeImportEmptySource);
      return;
    }
    final result = importTerminalTheme(source, nameHint: _name.text);
    if (!result.isSuccess) {
      setState(
        () => _error = l10n.terminalThemeImportErrorMessage(result.error!),
      );
      return;
    }
    Navigator.of(context).pop(result);
  }
}

/// Turns `…/themes/tokyo-night_storm.toml` into `tokyo night storm`-ish title
/// case, so the file name seeds a readable theme name.
String _themeNameFromPath(String path) {
  final base = path.split(RegExp(r'[/\\]')).last;
  final dot = base.lastIndexOf('.');
  final stem = dot > 0 ? base.substring(0, dot) : base;
  final words = stem
      .split(RegExp(r'[-_\s]+'))
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1));
  return words.isEmpty ? stem : words.join(' ');
}
