import 'package:flutter/material.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../theme/app_fonts.dart';
import '../../theme/app_typography_scale.dart';
import '../../utils/ui/app_keys.dart';
import 'pairing_nav_bar.dart';

/// Read-only unified diff of one changed file in the mirrored pane's repository.
///
/// [cubit] is passed rather than read from the tree: this route is pushed from a
/// modal bottom sheet, which sits above the provider the sheet's caller holds.
Future<void> showMirrorDiff(
  BuildContext context,
  PairingClientCubit cubit, {
  required String path,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _MirrorDiffPage(cubit: cubit, path: path),
    ),
  );
}

class _MirrorDiffPage extends StatefulWidget {
  const _MirrorDiffPage({required this.cubit, required this.path});

  final PairingClientCubit cubit;
  final String path;

  @override
  State<_MirrorDiffPage> createState() => _MirrorDiffPageState();
}

class _MirrorDiffPageState extends State<_MirrorDiffPage> {
  List<String>? _lines;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final diff = await widget.cubit.gitDiff(widget.path);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = diff == null;
      // `split` on an empty string yields one empty line, which would render as
      // a blank body instead of the "no diff" message.
      _lines = diff == null || diff.isEmpty
          ? const []
          : diff.replaceAll('\r\n', '\n').split('\n');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: AppKeys.pairingMirrorDiffPage,
      body: SafeArea(
        child: Column(
          children: [
            PairingNavBar(
              title: _basename(widget.path),
              onBack: () => Navigator.of(context).maybePop(),
              trailing: PairingNavAction(
                icon: Icons.refresh,
                tooltip: context.l10n.gitRefresh,
                iconSize: 22,
                onTap: _load,
              ),
            ),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  static String _basename(String path) {
    // Host paths are POSIX-relative from git, but a Windows repo reports `/`
    // too (`core.quotePath=false` aside, porcelain always uses forward slashes).
    final cut = path.lastIndexOf('/');
    return cut < 0 ? path : path.substring(cut + 1);
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final cs = Theme.of(context).colorScheme;
    final lines = _lines ?? const <String>[];
    if (_failed || lines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _failed ? context.l10n.pairingDiffFailed : context.l10n.pairingDiffEmpty,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    final style = appMonoTextStyle(
      context,
      fontSize: context.appTypography.bodySmall,
    );
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: lines.length,
      itemBuilder: (context, index) => _DiffLine(
        text: lines[index],
        style: style,
      ),
    );
  }
}

/// One diff line, tinted by its leading marker.
///
/// Lines soft-wrap rather than scrolling horizontally: on a phone a 120-column
/// line is unreadable either way, and a horizontal scroll under a vertical list
/// costs the reader a gesture per line to see the end of it.
class _DiffLine extends StatelessWidget {
  const _DiffLine({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (Color? background, Color foreground) = switch (_kindOf(text)) {
      _DiffLineKind.added => (
        cs.primary.withValues(alpha: 0.14),
        cs.onSurface,
      ),
      _DiffLineKind.removed => (
        cs.error.withValues(alpha: 0.12),
        cs.onSurface,
      ),
      _DiffLineKind.hunk => (
        cs.surfaceContainerHighest,
        cs.onSurfaceVariant,
      ),
      _DiffLineKind.header => (null, cs.onSurfaceVariant),
      _DiffLineKind.context => (null, cs.onSurface),
    };
    return Container(
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Text(text, style: style.copyWith(color: foreground)),
    );
  }

  /// Order matters: `+++`/`---` are file headers and must be classified before
  /// the single-character `+`/`-` body markers they start with.
  static _DiffLineKind _kindOf(String line) {
    if (line.startsWith('@@')) return _DiffLineKind.hunk;
    if (line.startsWith('+++') ||
        line.startsWith('---') ||
        line.startsWith('diff --git') ||
        line.startsWith('index ') ||
        line.startsWith('new file') ||
        line.startsWith('deleted file') ||
        line.startsWith('similarity index') ||
        line.startsWith('rename ') ||
        line.startsWith('\\ No newline')) {
      return _DiffLineKind.header;
    }
    if (line.startsWith('+')) return _DiffLineKind.added;
    if (line.startsWith('-')) return _DiffLineKind.removed;
    return _DiffLineKind.context;
  }
}

enum _DiffLineKind { added, removed, hunk, header, context }
