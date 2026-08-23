import 'dart:async';

import 'package:flutter/material.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/pairing/pairing_git_view.dart';
import '../../theme/app_fonts.dart';
import '../../utils/ui/app_keys.dart';
import 'mirror_diff_page.dart';
import 'pairing_nav_bar.dart';
import 'pairing_sheet_parts.dart';

/// Bottom sheet listing what changed in the repository the mirrored pane sits
/// in — the phone's answer to "what did the agent just do".
///
/// A sheet rather than a pushed page on purpose: the terminal stays visible
/// behind it, so the reader can keep an eye on a still-running turn.
///
/// [cubit] is passed rather than read from the tree because the sheet's own
/// `showMirrorDiff` route is pushed above the modal barrier, past the provider.
Future<void> showMirrorChangesSheet(
  BuildContext context,
  PairingClientCubit cubit,
) {
  return showPairingSheet<void>(
    context: context,
    builder: (_) => _MirrorChangesSheet(cubit: cubit),
  );
}

class _MirrorChangesSheet extends StatefulWidget {
  const _MirrorChangesSheet({required this.cubit});

  final PairingClientCubit cubit;

  @override
  State<_MirrorChangesSheet> createState() => _MirrorChangesSheetState();
}

class _MirrorChangesSheetState extends State<_MirrorChangesSheet> {
  PairingGitChanges? _changes;
  bool _loading = true;
  bool _failed = false;
  StreamSubscription<void>? _hints;

  @override
  void initState() {
    super.initState();
    _load();
    // The agent finishing a turn is the one moment this list is stale in a way
    // the reader cares about, and they are usually watching the terminal rather
    // than pulling to refresh.
    _hints = widget.cubit.gitRefreshHints.listen((_) => _load());
  }

  @override
  void dispose() {
    _hints?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final changes = await widget.cubit.gitChanges();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = changes == null;
      _changes = changes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final changes = _changes;
    final branch = changes?.branch ?? '';
    return SafeArea(
      top: false,
      child: Column(
        key: AppKeys.pairingMirrorChangesSheet,
        mainAxisSize: MainAxisSize.min,
        children: [
          const PairingSheetGrab(),
          PairingSheetHead(
            title: context.l10n.gitChanges,
            onClose: () => Navigator.of(context).maybePop(),
          ),
          if (branch.isNotEmpty)
            PairingSheetSubtitle(context.l10n.pairingChangesBranch(branch)),
          Flexible(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final changes = _changes;
    if (_failed) return _message(context, context.l10n.pairingChangesFailed);
    if (changes == null || !changes.isRepository) {
      return _message(context, context.l10n.gitNotARepository);
    }
    if (changes.files.isEmpty) {
      return _message(context, context.l10n.gitNoChanges);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 12),
        itemCount: changes.files.length,
        itemBuilder: (context, index) => _ChangeRow(
          file: changes.files[index],
          cubit: widget.cubit,
        ),
      ),
    );
  }

  Widget _message(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.file, required this.cubit});

  final PairingGitFile file;
  final PairingClientCubit cubit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cut = file.path.lastIndexOf('/');
    final name = cut < 0 ? file.path : file.path.substring(cut + 1);
    final folder = cut < 0 ? '' : file.path.substring(0, cut);
    return InkWell(
      // A pushed route, not a nested sheet: a diff is a full screen of content
      // and the reader needs the whole height for it.
      onTap: () => showMirrorDiff(context, cubit, path: file.path),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            _Badge(badge: file.badge),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (folder.isNotEmpty)
                    Text(
                      folder,
                      maxLines: 1,
                      // The interesting end of a long path is its tail, so the
                      // ellipsis goes at the front.
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: pairingMutedColor(cs),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 20, color: pairingMutedColor(cs)),
          ],
        ),
      ),
    );
  }
}

/// Git's single-letter status code, coloured by meaning.
class _Badge extends StatelessWidget {
  const _Badge({required this.badge});

  final String badge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Unknown codes fall back to the neutral colour rather than being hidden —
    // the letter is the host's, and a new one must still be readable here.
    final color = switch (badge) {
      'A' || '?' => cs.primary,
      'D' => cs.error,
      'U' => cs.error,
      _ => cs.tertiary,
    };
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        badge,
        style: appMonoTextStyle(
          context,
          fontSize: 12,
          color: color,
        ).copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Nav-bar entry point for [showMirrorChangesSheet], with the changed-file count
/// as a badge.
///
/// [count] null means "unknown" (not a repository, or the host could not be
/// asked) and shows a bare icon — deliberately not `0`, which would claim the
/// repo is clean when nothing was actually read.
class MirrorChangesAction extends StatelessWidget {
  const MirrorChangesAction({super.key, required this.count, required this.onTap});

  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final action = PairingNavAction(
      key: AppKeys.pairingMirrorChangesButton,
      icon: Icons.difference_outlined,
      tooltip: context.l10n.gitChanges,
      iconSize: 22,
      onTap: onTap,
    );
    final badge = count;
    if (badge == null || badge == 0) return action;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        action,
        Positioned(
          right: 4,
          top: 8,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                // Past two digits the exact number stops informing the decision
                // to open the sheet, and a third digit would outgrow the glyph.
                badge > 99 ? '99+' : '$badge',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: cs.onPrimary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
