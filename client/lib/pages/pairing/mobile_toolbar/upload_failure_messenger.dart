import 'dart:async';

import 'package:flutter/material.dart';

import '../../../cubits/image_upload_cubit.dart';
import '../../../l10n/l10n_extensions.dart';

/// Turns [ImageUploadCubit.failures] into snack bars.
///
/// A widget rather than a `BlocListener` because a failure is an event, not
/// state — after a failure the cubit returns to [ImageUploadStatus.idle], which
/// is indistinguishable from never having uploaded. A `BlocListener` keyed off
/// state would either miss the event or refire on the next unrelated idle.
class UploadFailureMessenger extends StatefulWidget {
  const UploadFailureMessenger({
    super.key,
    required this.failures,
    required this.child,
    this.maxMb = 25,
  });

  final Stream<ImageUploadFailure> failures;
  final Widget child;

  /// The size limit, in megabytes, named in the `tooLarge` copy. Passed in so
  /// the ceiling lives in exactly one place (the cubit's `maxBytes`).
  final int maxMb;

  @override
  State<UploadFailureMessenger> createState() => _UploadFailureMessengerState();
}

class _UploadFailureMessengerState extends State<UploadFailureMessenger> {
  StreamSubscription<ImageUploadFailure>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.failures.listen(_show);
  }

  void _show(ImageUploadFailure failure) {
    // A late result can arrive after the panel is gone; showing a snack bar
    // then would dereference a dead context.
    if (!mounted) return;
    final l10n = context.l10n;
    final message = switch (failure) {
      ImageUploadFailure.tooLarge => l10n.imageUploadTooLarge(widget.maxMb),
      ImageUploadFailure.unsupportedType => l10n.imageUploadUnsupportedType,
      ImageUploadFailure.failed => l10n.imageUploadFailed,
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
