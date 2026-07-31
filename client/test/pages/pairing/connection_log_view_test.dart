import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/pairing_client_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/repositories/pairing_settings_repository.dart';
import 'package:teampilot/pages/pairing/connection_log_view.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

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
        home: Scaffold(
          body: BlocProvider<PairingClientCubit>.value(
            value: cubit,
            child: const ConnectionLogView(),
          ),
        ),
      ),
    );
  }

  testWidgets('empty log shows the waiting placeholder', (tester) async {
    await pump(tester);
    expect(find.byKey(AppKeys.pairingConnectionLog), findsOneWidget);
    expect(find.text('Waiting for connection…'), findsOneWidget);
  });

  testWidgets('logged lines render newest-first', (tester) async {
    cubit.set(
      const PairingClientState(logs: ['step one', 'step two']),
    );
    await pump(tester);

    expect(find.text('Waiting for connection…'), findsNothing);
    expect(find.text('step one'), findsOneWidget);
    expect(find.text('step two'), findsOneWidget);
  });
}
