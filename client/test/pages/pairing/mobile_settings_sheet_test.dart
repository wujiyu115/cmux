import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/voice_input_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/pairing/mobile_settings_sheet.dart';
import 'package:teampilot/repositories/voice_input_repository.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/fake_stt_provider.dart';

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
    final voice = VoiceInputCubit(
      repository: InMemoryVoiceInputRepository(),
      providerFactory: (_, _) => FakeSttProvider(),
    );
    addTearDown(voice.close);
    await voice.load();

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

    unawaited(showMobileSettingsSheet(ctx, voiceCubit: voice));
    await tester.pumpAndSettle();

    // The sheet renders and reuses the language control from onboarding.
    expect(find.byKey(AppKeys.mobileSettingsSheet), findsOneWidget);
    expect(find.byKey(AppKeys.languageSystemButton), findsOneWidget);

    // The close affordance dismisses it.
    await tester.tap(find.byKey(AppKeys.mobileSettingsCloseButton));
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.mobileSettingsSheet), findsNothing);
  });

  testWidgets('the voice row opens voice settings', (tester) async {
    // The sheet mounts in the root navigator, above the shell's voice cubit, so
    // the entry point can only work if showMobileSettingsSheet re-provides it.
    final layout = LayoutCubit();
    addTearDown(layout.close);
    final voice = VoiceInputCubit(
      repository: InMemoryVoiceInputRepository(),
      providerFactory: (_, _) => FakeSttProvider(),
    );
    addTearDown(voice.close);
    await voice.load();

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

    unawaited(showMobileSettingsSheet(ctx, voiceCubit: voice));
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.mobileSettingsVoiceRow), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.mobileSettingsVoiceRow));
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.voiceSettingsPage), findsOneWidget);
  });
}
