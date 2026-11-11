import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/pane_mode.dart';
import 'package:teampilot/pages/pairing/host_pane_defaults_page.dart';
import 'package:teampilot/repositories/pairing_settings_repository.dart';
import 'package:teampilot/services/pairing/host_settings_client.dart';
import 'package:teampilot/services/pairing/pairing_client.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

const _desktop = PairedDesktop(
  id: 'desk-1',
  name: 'Studio PC',
  wsUrls: ['ws://127.0.0.1:47821/pair/ws'],
  hostPublicKeyB64: 'pk',
  deviceToken: 'token',
);

/// Answers from memory: no socket, no host, but the same shape the real client
/// hands back (the host's normalised values, not the request).
class _FakeHostClient extends HostSettingsClient {
  _FakeHostClient({
    this.defaults,
    this.failRead = false,
    this.failWrite = false,
  });

  PairingPaneDefaults? defaults;
  final bool failRead;
  final bool failWrite;
  final writes = <(PaneMode, String)>[];

  @override
  Future<PairingPaneDefaults> readPaneDefaults(PairedDesktop desktop) async {
    if (failRead) throw Exception('host unreachable');
    return defaults ??
        const PairingPaneDefaults(
          mode: PaneMode.terminal,
          chatAgentCommand: 'claude',
        );
  }

  @override
  Future<PairingPaneDefaults> writePaneDefaults(
    PairedDesktop desktop, {
    required PaneMode mode,
    required String chatAgentCommand,
  }) async {
    if (failWrite) throw Exception('write failed');
    writes.add((mode, chatAgentCommand));
    // Empty command comes back as the host's default, exactly like the desktop.
    final stored = chatAgentCommand.trim().isEmpty
        ? 'claude'
        : chatAgentCommand;
    defaults = PairingPaneDefaults(mode: mode, chatAgentCommand: stored);
    return defaults!;
  }
}

Widget _wrap(Widget child) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: child,
    ),
  );
}

void main() {
  testWidgets('shows the host defaults it read', (tester) async {
    final client = _FakeHostClient(
      defaults: const PairingPaneDefaults(
        mode: PaneMode.chat,
        chatAgentCommand: 'bash -lc pi',
      ),
    );
    await tester.pumpWidget(
      _wrap(HostPaneDefaultsPage(desktop: _desktop, client: client)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Studio PC · ws://127.0.0.1:47821/pair/ws'), findsOne);
    expect(find.text('bash -lc pi'), findsOne);
    // The host's address is the subtitle: this edits *that* machine only.
    expect(find.text('Desktop window defaults'), findsOne);
  });

  testWidgets('switching the mode writes it to the desktop', (tester) async {
    final client = _FakeHostClient();
    await tester.pumpWidget(
      _wrap(HostPaneDefaultsPage(desktop: _desktop, client: client)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();

    expect(client.writes.single.$1, PaneMode.chat);
    expect(find.text('Saved to the desktop'), findsOne);
  });

  testWidgets('an unreachable desktop offers a retry instead of a form', (
    tester,
  ) async {
    final client = _FakeHostClient(failRead: true);
    await tester.pumpWidget(
      _wrap(HostPaneDefaultsPage(desktop: _desktop, client: client)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Cannot reach this desktop'), findsOne);
    expect(find.byKey(AppKeys.hostPaneDefaultsCommandField), findsNothing);
    expect(find.text('Retry'), findsOne);
  });

  testWidgets('a failed write reloads the host value and says so', (
    tester,
  ) async {
    final client = _FakeHostClient(failWrite: true);
    await tester.pumpWidget(
      _wrap(HostPaneDefaultsPage(desktop: _desktop, client: client)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();

    expect(client.writes, isEmpty);
    expect(
      find.text('Could not save; reloaded the desktop\'s current values'),
      findsOne,
    );
    // Rolled back to the value the host reported, not the one tapped.
    expect(find.text('claude'), findsOne);
  });
}
