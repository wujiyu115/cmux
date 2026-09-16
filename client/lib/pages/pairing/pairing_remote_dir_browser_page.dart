import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/pairing/pairing_client.dart';
import '../../theme/app_fonts.dart';
import 'pairing_block_button.dart';
import 'pairing_nav_bar.dart';

/// Full-screen browser over the paired desktop's directories, used to pick an
/// existing folder when creating a workspace. Pops the selected absolute path,
/// or null when dismissed.
///
/// Windows machines additionally list their drive roots as jump targets, at the
/// top of every listing — see [PairingDirListing.roots]. The drives block is the
/// only way to reach a volume other than the one the browse opened on, since a
/// single directory tree cannot name its siblings.
///
/// [cubit] is captured by the caller (the create-workspace sheet), which already
/// holds it above the modal barrier. [target] is the machine to browse — null
/// leaves the choice to the host's default plane.
Future<String?> showPairingRemoteDirBrowser(
  BuildContext context,
  PairingClientCubit cubit, {
  String? initialPath,
  PairingTarget? target,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => _PairingRemoteDirBrowserPage(
        cubit: cubit,
        initialPath: initialPath,
        target: target,
      ),
      fullscreenDialog: true,
    ),
  );
}

class _PairingRemoteDirBrowserPage extends StatefulWidget {
  const _PairingRemoteDirBrowserPage({
    required this.cubit,
    this.initialPath,
    this.target,
  });

  final PairingClientCubit cubit;
  final String? initialPath;

  /// Whose filesystem this is listing. Also the subtitle: on a desktop with more
  /// than one machine, a bare path does not say which one it came from.
  final PairingTarget? target;

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
    final result = await widget.cubit.browseDir(
      path: path,
      targetId: widget.target?.id,
    );
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

  /// Ascends one level. A drive root's parent is itself, so the browser stops
  /// there and the drives block is how you leave it for another volume.
  void _up(String parent) => _load(parent);

  /// Jumps to a drive root shown in the drives block.
  void _openRoot(String root) => _load(root);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final listing = _listing;
    final target = widget.target;
    // A listed directory is the only thing worth confirming, so the button waits
    // for one: `path` is empty until the first listing arrives.
    final hasDirectory = listing != null && listing.path.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PairingNavBar(
              // Name the machine when the host offered a choice, so a bare
              // `/home/me` cannot be mistaken for the wrong one. The label is
              // host-rendered and shown verbatim.
              title: target == null
                  ? l10n.pairingBrowseTitle
                  : l10n.pairingBrowseTitleOn(target.label),
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
                  // Drives sit above any directory, so there is no path to show
                  // until one is entered.
                  listing.path.isEmpty
                      ? l10n.pairingBrowseThisComputer
                      : listing.path,
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
                      onOpenRoot: _openRoot,
                      onUp: _up,
                    ),
            ),
            if (hasDirectory)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  spacing.lg,
                  spacing.sm,
                  spacing.lg,
                  spacing.md,
                ),
                child: PairingBlockButton(
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
  const _DirList({
    required this.listing,
    required this.onEnter,
    required this.onOpenRoot,
    required this.onUp,
  });

  final PairingDirListing? listing;
  final ValueChanged<String?> onEnter;
  final ValueChanged<String> onOpenRoot;
  final ValueChanged<String> onUp;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    if (listing == null) return const SizedBox.shrink();
    final parent = listing!.parent;
    final dirs = listing!.dirs;
    final roots = listing!.roots;
    final current = listing!.path;
    // A listed directory whose parent is null is a root the browser won't ascend
    // past. When the machine also has drive roots, that is a dead end — offer a
    // way back up to the drives block, where the other volumes are.
    final strandedAtRoot =
        parent == null && current.isNotEmpty && roots.isNotEmpty;

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: spacing.lg),
      children: [
        if (parent != null)
          _Row(
            icon: Icons.arrow_upward,
            label: l10n.pairingParentDirectory,
            muted: true,
            onTap: () => onUp(parent),
          )
        else if (strandedAtRoot)
          _Row(
            icon: Icons.arrow_upward,
            label: l10n.pairingParentDirectory,
            muted: true,
            onTap: () => onEnter(null),
          ),
        for (final root in roots)
          _Row(
            icon: Icons.storage_rounded,
            label: root,
            selected: _isCurrentDrive(current, root),
            onTap: () => onOpenRoot(root),
          ),
        if (dirs.isEmpty && parent == null && roots.isEmpty)
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
                _join(current, name),
              ),
            ),
      ],
    );
  }

  /// Whether [path] sits on the drive [root] names. Compares the lowercased
  /// drive letter rather than a prefix, so `C:\` is not "inside" `C:\Users` and
  /// an odd separator style cannot break the match.
  static bool _isCurrentDrive(String path, String root) {
    String drive(String value) {
      final colon = value.indexOf(':');
      return colon <= 0 ? '' : value.substring(0, colon).toLowerCase();
    }

    final pathDrive = drive(path);
    return pathDrive.isNotEmpty && pathDrive == drive(root);
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
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool muted;

  /// The row names the location currently being listed (a drive root the user
  /// just entered), so it reads as a position in the tree rather than an action.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final color = selected
        ? cs.primary
        : (muted ? cs.onSurfaceVariant : cs.onSurface);
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
                    style: TextStyle(
                      fontSize: 16,
                      color: color,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (selected)
                  Text(
                    context.l10n.pairingBrowseCurrentDrive,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
