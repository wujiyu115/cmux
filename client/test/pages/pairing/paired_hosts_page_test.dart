import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/pairing_client_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/repositories/pairing_settings_repository.dart';
import 'package:teampilot/pages/pairing/paired_hosts_page.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

class _TestCubit extends PairingClientCubit {
  _TestCubit(PairingSettingsRepository settings) : super(settings: settings);
  void set(PairingClientState s) => emit(s);
}

const _desktop = PairedDesktop(
  id: 'd1',
  name: 'Studio Desktop',
  wsUrls: ['ws://192.168.1.5:5555/pair/ws'],
  hostPublicKeyB64: 'pk',
  deviceToken: 't',
);

void main() {
  late _TestCubit cubit;
  late InMemoryPairingSettingsRepository settings;

  setUp(() {
    settings = InMemoryPairingSettingsRepository();
    cubit = _TestCubit(settings);
  });
  tearDown(() => cubit.close());

  Future<void> pump(WidgetTester tester, {required VoidCallback onScan}) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<PairingClientCubit>.value(
          value: cubit,
          child: PairedHostsPage(onScan: onScan),
        ),
      ),
    );
  }

  testWidgets('empty state points at the scanner and both Scan actions fire',
      (tester) async {
    var scans = 0;
    await pump(tester, onScan: () => scans++);

    expect(find.byKey(AppKeys.pairedHostsPage), findsOneWidget);
    expect(find.text('No paired desktops yet.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Scan QR code'));
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Scan'));
    expect(scans, 2);
  });

  testWidgets('paired desktops render as tiles', (tester) async {
    cubit.set(const PairingClientState(pairedDesktops: [_desktop]));
    await pump(tester, onScan: () {});

    expect(find.byKey(const ValueKey('paired-desktop-d1')), findsOneWidget);
    expect(find.text('Studio Desktop'), findsOneWidget);
    expect(find.text('ws://192.168.1.5:5555/pair/ws'), findsOneWidget);
    expect(find.text('No paired desktops yet.'), findsNothing);
  });

  testWidgets('the remove button drops the desktop back to the empty state',
      (tester) async {
    await settings.savePairedDesktops(const [_desktop]);
    cubit.set(const PairingClientState(pairedDesktops: [_desktop]));
    await pump(tester, onScan: () {});

    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('paired-desktop-d1')), findsNothing);
    expect(find.text('No paired desktops yet.'), findsOneWidget);
    expect(await settings.loadPairedDesktops(), isEmpty);
  });
}
