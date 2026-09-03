import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/pairing/mirror_actions_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host({required ValueChanged<MirrorAction?> onResult}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: OutlinedButton(
            onPressed: () async {
              onResult(
                await showMirrorActionsSheet(context, changeCount: 14),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('git diff entry returns gitDiff and carries the count',
      (tester) async {
    MirrorAction? result;
    await tester.pumpWidget(host(onResult: (a) => result = a));
    await openSheet(tester);

    expect(find.text('Git diff'), findsOneWidget);
    expect(find.text('14 changed'), findsOneWidget);
    expect(find.text('Scroll to latest'), findsOneWidget);

    await tester.tap(find.text('Git diff'));
    await tester.pumpAndSettle();
    expect(result, MirrorAction.gitDiff);
  });

  testWidgets('scroll entry returns scrollToLatest', (tester) async {
    MirrorAction? result;
    await tester.pumpWidget(host(onResult: (a) => result = a));
    await openSheet(tester);

    await tester.tap(find.text('Scroll to latest'));
    await tester.pumpAndSettle();
    expect(result, MirrorAction.scrollToLatest);
  });

  testWidgets('unknown or clean count shows no counter on the diff row',
      (tester) async {
    for (final count in [null, 0]) {
      MirrorAction? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: OutlinedButton(
                  onPressed: () async {
                    result = await showMirrorActionsSheet(
                      context,
                      changeCount: count,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await openSheet(tester);

      expect(find.text('0 changed'), findsNothing);
      expect(find.textContaining('changed'), findsNothing,
          reason: 'count=$count must not claim a clean repo');

      await tester.tap(find.text('Git diff'));
      await tester.pumpAndSettle();
      expect(result, MirrorAction.gitDiff);
    }
  });
}
