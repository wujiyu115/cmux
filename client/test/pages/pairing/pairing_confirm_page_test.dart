import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/pairing_client_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/pairing/pairing_confirm_page.dart';
import 'package:teampilot/repositories/pairing_settings_repository.dart';
import 'package:teampilot/services/pairing/pairing_client.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

/// Cubit that lets the widget test freeze any phase without a real socket.
class _TestCubit extends PairingClientCubit {
  _TestCubit() : super(settings: InMemoryPairingSettingsRepository());
  void set(PairingClientState s) => emit(s);
}

void main() {
  late _TestCubit cubit;

  setUp(() => cubit = _TestCubit());
  tearDown(() => cubit.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<PairingClientCubit>.value(
          value: cubit,
          child: const PairingConfirmPage(),
        ),
      ),
    );
  }

  testWidgets('awaiting shows the intro + Connect + Cancel', (tester) async {
    cubit.set(
      const PairingClientState(phase: PairingClientPhase.confirmAwaiting),
    );
    await pump(tester);

    expect(find.byKey(AppKeys.pairingConfirmPage), findsOneWidget);
    expect(find.textContaining('Ready to pair'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(AppKeys.pairingConnectButton),
        matching: find.text('Connect'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(AppKeys.pairingConfirmCancelButton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the step rail renders one step per pairing stage',
      (tester) async {
    cubit.set(
      const PairingClientState(phase: PairingClientPhase.confirmAwaiting),
    );
    await pump(tester);

    expect(find.byKey(AppKeys.pairingStepRail), findsOneWidget);
    expect(find.text('Reach the desktop'), findsOneWidget);
    expect(find.text('Secure the channel'), findsOneWidget);
    expect(find.text('Check the pairing code'), findsOneWidget);
    expect(find.text('Sync workspaces'), findsOneWidget);
  });

  testWidgets('a done stage is checked and the failed one is crossed out',
      (tester) async {
    cubit.set(
      const PairingClientState(
        phase: PairingClientPhase.error,
        error: 'no route to host',
        stageStatuses: [
          PairingStageStatus.done,
          PairingStageStatus.fail,
          PairingStageStatus.idle,
          PairingStageStatus.idle,
        ],
      ),
    );
    await pump(tester);

    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    // The reason is stated once, in the footer — not repeated on the rail.
    expect(find.text('no route to host'), findsOneWidget);
  });

  testWidgets('connecting shows a spinner and hides Connect', (tester) async {
    cubit.set(
      const PairingClientState(phase: PairingClientPhase.confirmConnecting),
    );
    await pump(tester);

    expect(find.text('Connecting…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Connect'), findsNothing);
    expect(find.text('Retry'), findsNothing);
    // The primary button stays in place but is disabled mid-connect.
    final button = tester.widget<TpButton>(
      find.byKey(AppKeys.pairingConnectButton),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('error shows the message + Retry', (tester) async {
    cubit.set(
      const PairingClientState(
        phase: PairingClientPhase.error,
        error: 'firewall blocked the port',
      ),
    );
    await pump(tester);

    expect(find.text('firewall blocked the port'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(AppKeys.pairingConnectButton),
        matching: find.text('Retry'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the log summary counts lines', (tester) async {
    cubit.set(
      const PairingClientState(
        phase: PairingClientPhase.confirmConnecting,
        logs: ['a', 'b', 'c'],
      ),
    );
    await pump(tester);

    expect(find.text('Connection log'), findsOneWidget);
    expect(find.text('3 lines'), findsOneWidget);
  });

  testWidgets('the embedded connection log renders logged lines',
      (tester) async {
    cubit.set(
      const PairingClientState(
        phase: PairingClientPhase.confirmConnecting,
        logs: ['Connecting…', 'Handshake ok'],
      ),
    );
    await pump(tester);

    expect(find.byKey(AppKeys.pairingConnectionLog), findsOneWidget);
    expect(find.text('Handshake ok'), findsOneWidget);
  });

  testWidgets('tapping Cancel returns the flow to idle', (tester) async {
    cubit.set(
      const PairingClientState(phase: PairingClientPhase.confirmAwaiting),
    );
    await pump(tester);

    await tester.tap(find.byKey(AppKeys.pairingConfirmCancelButton));
    await tester.pump();

    expect(cubit.state.phase, PairingClientPhase.idle);
  });
}
