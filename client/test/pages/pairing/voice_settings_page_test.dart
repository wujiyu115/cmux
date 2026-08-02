import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/voice_input_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/pairing/voice/voice_settings_page.dart';
import 'package:teampilot/repositories/voice_input_repository.dart';
import 'package:teampilot/services/stt/stt_provider.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/fake_stt_provider.dart';

void main() {
  late InMemoryVoiceInputRepository repository;
  late VoiceInputCubit cubit;
  late FakeSttProvider provider;

  setUp(() {
    repository = InMemoryVoiceInputRepository();
    provider = FakeSttProvider();
    cubit = VoiceInputCubit(
      repository: repository,
      providerFactory: (_, _) => provider,
    );
  });

  tearDown(() => cubit.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider.value(
          value: cubit,
          child: const VoiceSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists every recognition service', (t) async {
    await cubit.load();
    await pump(t);
    expect(find.byKey(AppKeys.voiceSettingsPage), findsOneWidget);
    for (final type in SttProviderType.values) {
      expect(
        find.byKey(AppKeys.voiceSettingsProviderTile(type.name)),
        findsOneWidget,
        reason: type.name,
      );
    }
  });

  testWidgets('shows no credential fields for the system service', (t) async {
    await cubit.load();
    await pump(t);
    expect(
      find.byKey(AppKeys.voiceSettingsCredentialField('volcAppId')),
      findsNothing,
    );
    expect(find.byKey(AppKeys.voiceSettingsTestButton), findsNothing,
        reason: 'nothing to connect to');
  });

  testWidgets('picking Volcengine reveals its two fields and the test button',
      (t) async {
    await cubit.load();
    await pump(t);
    await t.tap(
      find.byKey(
        AppKeys.voiceSettingsProviderTile(SttProviderType.volcengine.name),
      ),
    );
    await t.pumpAndSettle();

    expect(cubit.state.provider, SttProviderType.volcengine);
    expect(repository.lastSavedPrefs!.provider, SttProviderType.volcengine);
    expect(
      find.byKey(AppKeys.voiceSettingsCredentialField('volcAppId')),
      findsOneWidget,
    );
    expect(
      find.byKey(AppKeys.voiceSettingsCredentialField('volcAccessToken')),
      findsOneWidget,
    );
    expect(find.byKey(AppKeys.voiceSettingsTestButton), findsOneWidget);
  });

  testWidgets('picking Alibaba reveals its three fields', (t) async {
    await cubit.load();
    await pump(t);
    await t.tap(
      find.byKey(
        AppKeys.voiceSettingsProviderTile(SttProviderType.aliyun.name),
      ),
    );
    await t.pumpAndSettle();

    for (final field in [
      'aliyunAccessKeyId',
      'aliyunAccessKeySecret',
      'aliyunAppKey',
    ]) {
      expect(
        find.byKey(AppKeys.voiceSettingsCredentialField(field)),
        findsOneWidget,
        reason: field,
      );
    }
  });

  testWidgets('typing a credential persists it on submit', (t) async {
    await cubit.load();
    await pump(t);
    await t.tap(
      find.byKey(
        AppKeys.voiceSettingsProviderTile(SttProviderType.volcengine.name),
      ),
    );
    await t.pumpAndSettle();

    await t.enterText(
      find.byKey(AppKeys.voiceSettingsCredentialField('volcAppId')),
      'the-app-id',
    );
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();

    expect(cubit.state.credentials.volcAppId, 'the-app-id');
  });

  testWidgets('obscures the secret fields but not the identifiers', (t) async {
    // An access token read over someone's shoulder is a billable credential.
    await cubit.load();
    await pump(t);
    await t.tap(
      find.byKey(
        AppKeys.voiceSettingsProviderTile(SttProviderType.volcengine.name),
      ),
    );
    await t.pumpAndSettle();

    TextField fieldFor(String name) => t.widget<TextField>(
      find.byKey(AppKeys.voiceSettingsCredentialField(name)),
    );
    expect(fieldFor('volcAccessToken').obscureText, isTrue);
    expect(fieldFor('volcAppId').obscureText, isFalse);
  });

  testWidgets('shows the cloud privacy note only for cloud services', (t) async {
    await cubit.load();
    await pump(t);
    final note = find.textContaining('not through the encrypted pairing');
    expect(note, findsNothing, reason: 'on-device recognition sends nothing');

    await t.tap(
      find.byKey(
        AppKeys.voiceSettingsProviderTile(SttProviderType.aliyun.name),
      ),
    );
    await t.pumpAndSettle();
    expect(note, findsOneWidget);
  });

  testWidgets('the language row defaults to following the system', (t) async {
    await cubit.load();
    await pump(t);
    expect(find.text('System default'), findsOneWidget);
  });

  testWidgets('picking a language persists it', (t) async {
    await cubit.load();
    await pump(t);
    await t.tap(find.byKey(AppKeys.voiceSettingsLanguageTile));
    await t.pumpAndSettle();
    await t.tap(find.text('简体中文').last);
    await t.pumpAndSettle();

    expect(cubit.state.localeId, isNotEmpty);
    expect(repository.lastSavedPrefs!.localeId, cubit.state.localeId);
  });

  testWidgets('a passing connection test reports the latency', (t) async {
    await cubit.load();
    await pump(t);
    await t.tap(
      find.byKey(
        AppKeys.voiceSettingsProviderTile(SttProviderType.volcengine.name),
      ),
    );
    await t.pumpAndSettle();

    provider.testConnectionMillis = 137;
    await t.tap(find.byKey(AppKeys.voiceSettingsTestButton));
    await t.pumpAndSettle();

    expect(find.text('Connected in 137 ms'), findsOneWidget);
  });

  testWidgets('a failing connection test says so', (t) async {
    await cubit.load();
    await pump(t);
    await t.tap(
      find.byKey(
        AppKeys.voiceSettingsProviderTile(SttProviderType.volcengine.name),
      ),
    );
    await t.pumpAndSettle();

    provider.testConnectionError = const SttException('bad key');
    await t.tap(find.byKey(AppKeys.voiceSettingsTestButton));
    await t.pumpAndSettle();

    expect(find.text('Connection failed'), findsOneWidget);
  });

  testWidgets('route() pushes the page with the cubit still in scope', (
    t,
  ) async {
    // The route helper exists so a caller cannot forget to re-provide the cubit
    // across the route boundary; this fails with ProviderNotFoundException if
    // the BlocProvider.value inside route() is ever dropped.
    await cubit.load();
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider.value(
          value: cubit,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).push(VoiceSettingsPage.route(cubit)),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.byKey(AppKeys.voiceSettingsPage), findsOneWidget);
  });
}
