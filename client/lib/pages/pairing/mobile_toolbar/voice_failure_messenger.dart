import 'dart:async';

import 'package:flutter/material.dart';

import '../../../cubits/voice_input_cubit.dart';
import '../../../l10n/l10n_extensions.dart';

/// Turns [VoiceInputCubit.failures] into snack bars.
///
/// A widget rather than a `BlocListener` because a failure is an event, not
/// state — a recognition error leaves the cubit back at [VoiceInputStatus.idle],
/// which is indistinguishable from never having started.
class VoiceFailureMessenger extends StatefulWidget {
  const VoiceFailureMessenger({
    super.key,
    required this.failures,
    required this.child,
  });

  final Stream<VoiceInputFailure> failures;
  final Widget child;

  @override
  State<VoiceFailureMessenger> createState() => _VoiceFailureMessengerState();
}

class _VoiceFailureMessengerState extends State<VoiceFailureMessenger> {
  StreamSubscription<VoiceInputFailure>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.failures.listen(_show);
  }

  void _show(VoiceInputFailure failure) {
    // A late result can arrive after the panel is gone; showing a snack bar
    // then would dereference a dead context.
    if (!mounted) return;
    final l10n = context.l10n;
    final message = switch (failure) {
      VoiceInputFailure.permissionDenied => l10n.voiceInputPermissionDenied,
      VoiceInputFailure.failed => l10n.voiceInputFailed,
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
