import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/pairing_client_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/pairing/pairing_confirm_page.dart';
import 'package:teampilot/repositories/pairing_settings_repository.dart';
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
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
    expect(find.byKey(AppKeys.pairingConfirmCancelButton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('connecting shows a spinner and hides Connect', (tester) async {
    cubit.set(
      const PairingClientState(phase: PairingClientPhase.confirmConnecting),
    );
    await pump(tester);

    expect(find.text('Connecting…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Connect'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsNothing);
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
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
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
