import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/app/boot_progress.dart';

/// Bootstrap gate UI. On desktop the native splash covers this until bootstrap
/// completes; on Android [flutter_native_splash] covers it until
/// [dismissBootSplash]. iOS has no native splash, so this *is* what the user
/// looks at while starting.
///
/// After [_stallAfter] it stops being just a logo and names the startup stage it
/// is waiting on. A bootstrap that hangs used to be indistinguishable from one
/// that crashed — both a blank white screen — and on a stock iOS device there is
/// no log file to consult. Anything past a few seconds is already abnormal, so
/// this costs nothing in the normal case and is the only clue in the bad one.
class AppBootstrapLoadingPage extends StatefulWidget {
  const AppBootstrapLoadingPage({super.key});

  static const _splashLogo = 'assets/icons/icon_bg.png';

  /// How long startup may sit silently before the page explains itself.
  static const _stallAfter = Duration(seconds: 8);

  @override
  State<AppBootstrapLoadingPage> createState() =>
      _AppBootstrapLoadingPageState();
}

class _AppBootstrapLoadingPageState extends State<AppBootstrapLoadingPage> {
  Timer? _stallTimer;
  var _stalled = false;

  @override
  void initState() {
    super.initState();
    _stallTimer = Timer(AppBootstrapLoadingPage._stallAfter, () {
      if (mounted) setState(() => _stalled = true);
    });
  }

  @override
  void dispose() {
    _stallTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Image(
              image: AssetImage(AppBootstrapLoadingPage._splashLogo),
              width: 256,
              height: 256,
              filterQuality: FilterQuality.medium,
            ),
            if (_stalled) const _StallDiagnostics(),
          ],
        ),
      ),
    );
  }
}

/// Names the stage startup is stuck on, and for how long.
///
/// Deliberately unlocalized: the reader is whoever is holding a build that will
/// not start, and the l10n delegates are themselves part of what may have failed
/// to load.
class _StallDiagnostics extends StatefulWidget {
  const _StallDiagnostics();

  @override
  State<_StallDiagnostics> createState() => _StallDiagnosticsState();
}

class _StallDiagnosticsState extends State<_StallDiagnostics> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The stuck duration is the load-bearing number, so it has to keep moving —
    // a frozen "12s" reads as a frozen UI.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ValueListenableBuilder<String>(
        valueListenable: BootProgress.stage,
        builder: (context, stage, _) {
          final stuckSeconds =
              (BootProgress.elapsedMs - BootProgress.enteredAtMs) ~/ 1000;
          return Column(
            children: [
              const Text(
                'Still starting…',
                style: TextStyle(color: Color(0xFF444444), fontSize: 14),
              ),
              const SizedBox(height: 6),
              Text(
                '$stage — ${stuckSeconds}s',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }
}
