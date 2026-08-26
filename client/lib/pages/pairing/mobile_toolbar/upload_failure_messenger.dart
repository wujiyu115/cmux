import 'dart:async';

import 'package:flutter/material.dart';

import '../../../cubits/media_upload_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../services/pairing/upload_limits.dart';

/// Turns [MediaUploadCubit.failures] into snack bars.
///
/// A widget rather than a `BlocListener` because a failure is an event, not
/// state — after a failure the cubit returns to [MediaUploadStatus.idle], which
/// is indistinguishable from never having uploaded. A `BlocListener` keyed off
/// state would either miss the event or refire on the next unrelated idle.
class UploadFailureMessenger extends StatefulWidget {
  const UploadFailureMessenger({
    super.key,
    required this.failures,
    required this.child,
  });

  final Stream<MediaUploadFailure> failures;
  final Widget child;

  @override
  State<UploadFailureMessenger> createState() => _UploadFailureMessengerState();
}

class _UploadFailureMessengerState extends State<UploadFailureMessenger> {
  StreamSubscription<MediaUploadFailure>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.failures.listen(_show);
  }

  void _show(MediaUploadFailure failure) {
    // A late result can arrive after the panel is gone; showing a snack bar
    // then would dereference a dead context.
    if (!mounted) return;
    final l10n = context.l10n;
    // The limit rides along with the event: an image and a video have different
    // ceilings, and only the cubit knows which one applied.
    final mb = ((failure.limitBytes ?? 0) / (1024 * 1024)).round();
    final message = switch (failure.reason) {
      MediaUploadFailureReason.tooLarge => switch (failure.kind) {
        UploadMediaKind.video => l10n.mediaUploadVideoTooLarge(mb),
        // An unknown kind cannot name a ceiling, so it degrades to the generic
        // line rather than claiming "larger than 0 MB".
        null => l10n.mediaUploadFailed,
        UploadMediaKind.image => l10n.mediaUploadImageTooLarge(mb),
      },
      MediaUploadFailureReason.unsupportedType =>
        l10n.mediaUploadUnsupportedType,
      MediaUploadFailureReason.failed => l10n.mediaUploadFailed,
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
