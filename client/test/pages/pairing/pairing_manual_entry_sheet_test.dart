import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/pairing/pairing_manual_entry_sheet.dart';
import 'package:teampilot/services/pairing/pairing_offer.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

void main() {
  const offer = PairingOffer(
    version: 1,
    wsUrls: ['ws://192.168.1.9:5555/pair/ws'],
    token: 'code',
    hostPublicKeyB64: 'PK',
    expiresAtMs: 0,
  );

  Future<PairingOffer?> open(WidgetTester tester) async {
    PairingOffer? result;
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  opened = true;
                  result = await showPairingManualEntrySheet(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    return result;
  }

  testWidgets('an unparseable code reports inline and keeps the sheet open',
      (tester) async {
    await open(tester);

    await tester.enterText(
      find.byKey(AppKeys.pairingManualEntryField),
      'not a pairing code',
    );
    await tester.tap(find.text('Pair'));
    await tester.pumpAndSettle();

    expect(find.text('Not a valid pairing code or link.'), findsOneWidget);
    expect(find.byKey(AppKeys.pairingManualEntrySheet), findsOneWidget);
  });

  testWidgets('typing clears a stale error', (tester) async {
    await open(tester);

    await tester.enterText(find.byKey(AppKeys.pairingManualEntryField), 'junk');
    await tester.tap(find.text('Pair'));
    await tester.pumpAndSettle();
    expect(find.text('Not a valid pairing code or link.'), findsOneWidget);

    await tester.enterText(find.byKey(AppKeys.pairingManualEntryField), 'j');
    await tester.pumpAndSettle();
    expect(find.text('Not a valid pairing code or link.'), findsNothing);
  });

  testWidgets('a valid deep link closes the sheet with the parsed offer',
      (tester) async {
    await open(tester);

    await tester.enterText(
      find.byKey(AppKeys.pairingManualEntryField),
      offer.toDeepLink(),
    );
    await tester.tap(find.text('Pair'));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.pairingManualEntrySheet), findsNothing);
  });

  testWidgets('cancel dismisses without an offer', (tester) async {
    await open(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.pairingManualEntrySheet), findsNothing);
  });
}
