import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/pairing/mobile_settings_sheet.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

Widget _wrap(LayoutCubit layout, {required Widget child}) {
  final theme = ThemeData(useMaterial3: true);
  return BlocProvider<LayoutCubit>.value(
    value: layout,
    child: MaterialApp(
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
    ),
  );
}

void main() {
  testWidgets('the sheet exposes the appearance controls and closes',
      (tester) async {
    final layout = LayoutCubit();
    addTearDown(layout.close);

    late BuildContext ctx;
    await tester.pumpWidget(
      _wrap(
        layout,
        child: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    unawaited(showMobileSettingsSheet(ctx));
    await tester.pumpAndSettle();

    // The sheet renders and reuses the language control from onboarding.
    expect(find.byKey(AppKeys.mobileSettingsSheet), findsOneWidget);
    expect(find.byKey(AppKeys.languageSystemButton), findsOneWidget);

    // The close affordance dismisses it.
    await tester.tap(find.byKey(AppKeys.mobileSettingsCloseButton));
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.mobileSettingsSheet), findsNothing);
  });
}
