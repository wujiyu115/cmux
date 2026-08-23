import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/widgets/settings/theme_color_preset_picker.dart';

/// Pumps the picker on a surface [width] wide — the default 800px test surface
/// clamps any wider `SizedBox`, which would keep the chips overflowing.
Future<void> _pumpAt(WidgetTester tester, double width) async {
  await tester.binding.setSurfaceSize(Size(width, 200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: 60,
            child: ThemeColorPresetPicker(selected: 'forest', onSelect: (_) {}),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('fades the clipped edge when the chips overflow', (tester) async {
    await _pumpAt(tester, 220);

    expect(find.byType(ShaderMask), findsOneWidget);
  });

  testWidgets('skips the fade layer when every chip fits', (tester) async {
    await _pumpAt(tester, 2000);

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.maxScrollExtent, 0);
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('keeps the fade after scrolling to the opposite end', (
    tester,
  ) async {
    await _pumpAt(tester, 220);

    // `reverse: true` starts pinned at the right, so only the left edge hides
    // chips. At the other end the hidden side — and so the faded one — swaps.
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.maxScrollExtent, greaterThan(0));
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(find.byType(ShaderMask), findsOneWidget);
  });
}
