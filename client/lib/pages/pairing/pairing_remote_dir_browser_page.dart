import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/pairing/pairing_client.dart';
import '../../theme/app_fonts.dart';
import 'pairing_nav_bar.dart';

/// Full-screen browser over the paired desktop's directories, used to pick an
/// existing folder when creating a workspace. Pops the selected absolute path,
/// or null when dismissed.
///
/// [cubit] is captured by the caller (the create-workspace sheet), which already
/// holds it above the modal barrier.
Future<String?> showPairingRemoteDirBrowser(
  BuildContext context,
  PairingClientCubit cubit, {
  String? initialPath,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) =>
          _PairingRemoteDirBrowserPage(cubit: cubit, initialPath: initialPath),
      fullscreenDialog: true,
    ),
  );
}

class _PairingRemoteDirBrowserPage extends StatefulWidget {
  const _PairingRemoteDirBrowserPage({
    required this.cubit,
    this.initialPath,
  });

  final PairingClientCubit cubit;
  final String? initialPath;

  @override
  State<_PairingRemoteDirBrowserPage> createState() =>
      _PairingRemoteDirBrowserPageState();
}

class _PairingRemoteDirBrowserPageState
    extends State<_PairingRemoteDirBrowserPage> {
  PairingDirListing? _listing;
  bool _loading = true;

  /// The host's reason for the last refused listing. Kept alongside [_listing]
  /// rather than replacing it: a failed step into a subdirectory should leave
  /// the parent listing usable and just say what went wrong.
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(widget.initialPath);
  }

  Future<void> _load(String? path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.cubit.browseDir(path);
    if (!mounted) return;
    setState(() {
      _loading = false;
      // Keep the previous listing on failure so the user isn't stranded on a
      // blank page — but say why, rather than looking like an empty folder.
      if (result.ok) {
        _listing = result.value;
      } else {
        _error = result.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final listing = _listing;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PairingNavBar(
              title: l10n.pairingBrowseTitle,
              onBack: () => Navigator.of(context).pop(),
            ),
            if (listing != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  spacing.lg,
                  spacing.sm,
                  spacing.lg,
                  spacing.sm,
                ),
                child: Text(
                  listing.path,
                  style: appMonoTextStyle(
                    context,
                    fontSize: 14,
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (_error != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  spacing.lg,
                  spacing.sm,
                  spacing.lg,
                  spacing.sm,
                ),
                child: Text(
                  // Localized headline plus the host's untranslatable reason,
                  // the same shape the create sheets use.
                  '${l10n.pairingBrowseFailed}\n$_error',
                  style: TextStyle(color: cs.error),
                ),
              ),
            Expanded(
              child: _loading && listing == null
                  ? const Center(child: CircularProgressIndicator())
                  : _DirList(
                      listing: listing,
                      onEnter: _load,
                    ),
            ),
            if (listing != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  spacing.lg,
                  spacing.sm,
                  spacing.lg,
                  spacing.md,
                ),
                child: TpButton(
                  onPressed: () => Navigator.of(context).pop(listing.path),
                  child: Text(l10n.pairingSelectThisFolder),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DirList extends StatelessWidget {
  const _DirList({required this.listing, required this.onEnter});

  final PairingDirListing? listing;
  final ValueChanged<String?> onEnter;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    if (listing == null) return const SizedBox.shrink();
    final parent = listing!.parent;
    final dirs = listing!.dirs;

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: spacing.lg),
      children: [
        if (parent != null)
          _Row(
            icon: Icons.arrow_upward,
            label: l10n.pairingParentDirectory,
            muted: true,
            onTap: () => onEnter(parent),
          ),
        if (dirs.isEmpty && parent == null)
          Padding(
            padding: EdgeInsets.symmetric(vertical: spacing.xl),
            child: Center(
              child: Text(
                l10n.pairingBrowseEmpty,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          )
        else
          for (final name in dirs)
            _Row(
              icon: Icons.folder_outlined,
              label: name,
              onTap: () => onEnter(
                _join(listing!.path, name),
              ),
            ),
      ],
    );
  }

  /// POSIX-style join for display navigation; the host re-normalizes with its
  /// own path context when it lists the child.
  String _join(String path, String name) =>
      path.endsWith('/') ? '$path$name' : '$path/$name';
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.onTap,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final color = muted ? cs.onSurfaceVariant : cs.onSurface;
    return InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: cs.outlineVariant)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.xs,
              vertical: spacing.sm,
            ),
            child: Row(
              children: [
                Icon(icon, size: context.tpIconSizes.md, color: color),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 16, color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
