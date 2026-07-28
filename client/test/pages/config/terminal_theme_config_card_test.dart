import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/config/terminal_theme/terminal_theme_config_card.dart';
import 'package:teampilot/repositories/user_terminal_theme_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/theme/terminal_theme_import.dart';
import 'package:teampilot/theme/terminal/cmux_terminal_theme.dart';
import 'package:teampilot/theme/terminal/user_terminal_theme_registry.dart';

import '../../support/post_frame_test_harness.dart';

/// Minimal Ghostty scheme: background/foreground plus all 8 normal ANSI slots
/// (the importer's fatal minimum); everything else is derived.
const String _ghosttySource = '''
background = #101820
foreground = #d0d4dc
palette = 0=#101820
palette = 1=#d04a62
palette = 2=#52c07e
palette = 3=#d4b85a
palette = 4=#5298d8
palette = 5=#b87cd8
palette = 6=#4eb8c4
palette = 7=#d0d4dc
''';

/// Pumps frames while also letting *real* async work run.
///
/// `testWidgets` bodies run in a fake-async zone where `dart:io` futures never
/// complete, so the import / delete handlers (which await the repository) would
/// hang forever under a plain `pump` / `pumpAndSettle`. Alternating
/// [WidgetTester.runAsync] with pumps drains the filesystem IO and then rebuilds.
Future<void> _flush(WidgetTester tester, {int rounds = 30}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
  }
  await tester.pump();
}

/// Drains the `AppToast` auto-dismiss timer (3s) so the test does not end with a
/// pending timer, then lets the exit animation finish.
Future<void> _drainToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  late Directory tempDir;
  late String themesDir;

  setUp(() {
    setUpTestAppStorage();
    tempDir = Directory.systemTemp.createTempSync('theme_card_test_');
    themesDir = p.join(tempDir.path, 'themes');
  });

  tearDown(() {
    UserTerminalThemeRegistry.instance.clear();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    tearDownTestAppStorage();
  });

  UserTerminalThemeRepository repo() => UserTerminalThemeRepository(
    fs: LocalFilesystem(),
    directory: themesDir,
  );

  Future<LayoutCubit> pumpCard(WidgetTester tester) async {
    final cubit = LayoutCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider.value(
          value: cubit,
          child: Scaffold(
            body: SingleChildScrollView(
              child: TerminalThemeConfigCard(repository: repo()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return cubit;
  }

  testWidgets('picking a theme writes its id via the cubit', (tester) async {
    final cubit = await pumpCard(tester);
    expect(cubit.state.preferences.terminalThemeMode, 'adaptive');

    await tester.ensureVisible(find.text('Dracula'));
    await tester.tap(find.text('Dracula'));
    await tester.pump();

    expect(cubit.state.preferences.terminalThemeMode, 'dracula');
  });

  testWidgets('custom colours toggle enables the slot editor', (tester) async {
    final cubit = await pumpCard(tester);
    expect(cubit.state.preferences.useCustomTerminalColors, isFalse);

    final switchFinder = find.byType(Switch);
    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pump();

    expect(cubit.state.preferences.useCustomTerminalColors, isTrue);

    // Slot fields become editable once the toggle is on.
    final field = find.byType(TextField).first;
    final widget = tester.widget<TextField>(field);
    expect(widget.enabled, isTrue);
  });

  testWidgets('invalid hex shows error and does not write; valid hex writes', (
    tester,
  ) async {
    final cubit = await pumpCard(tester);

    final switchFinder = find.byType(Switch);
    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pump();
    expect(cubit.state.preferences.useCustomTerminalColors, isTrue);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // First slot field is `background`.
    final field = find.byType(TextField).first;
    await tester.ensureVisible(field);

    await tester.enterText(field, 'zzz');
    await tester.pump();
    expect(find.text(l10n.terminalColorInvalidHex), findsOneWidget);
    expect(
      cubit.state.preferences.terminalColorOverrides.containsKey('background'),
      isFalse,
    );

    await tester.enterText(field, '#010203');
    await tester.pump();
    expect(find.text(l10n.terminalColorInvalidHex), findsNothing);
    expect(
      cubit.state.preferences.terminalColorOverrides['background'],
      0xFF010203,
    );
  });

  testWidgets('pasted theme is imported, listed, and selected', (tester) async {
    final cubit = await pumpCard(tester);

    await tester.ensureVisible(
      find.byKey(const Key('terminal-theme-import-action')),
    );
    await tester.tap(find.byKey(const Key('terminal-theme-import-action')));
    await _flush(tester);

    await tester.enterText(
      find.byKey(const Key('terminal-theme-import-name')),
      'Paste Theme',
    );
    await tester.enterText(
      find.byKey(const Key('terminal-theme-import-source')),
      _ghosttySource,
    );
    await tester.tap(find.byKey(const Key('terminal-theme-import-confirm')));
    await _flush(tester);

    // Persisted, cached for the synchronous mapper, and selected.
    expect(File(p.join(themesDir, 'paste-theme.json')).existsSync(), isTrue);
    expect(
      UserTerminalThemeRegistry.instance.byId('paste-theme'),
      isNotNull,
    );
    expect(cubit.state.preferences.terminalThemeMode, 'paste-theme');

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.terminalColorSchemeGroupImported), findsOneWidget);
    expect(find.text('Paste Theme'), findsWidgets);

    await _drainToast(tester);
  });

  testWidgets('malformed source shows an inline error and keeps the dialog', (
    tester,
  ) async {
    final cubit = await pumpCard(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.ensureVisible(
      find.byKey(const Key('terminal-theme-import-action')),
    );
    await tester.tap(find.byKey(const Key('terminal-theme-import-action')));
    await _flush(tester);

    await tester.enterText(
      find.byKey(const Key('terminal-theme-import-source')),
      'not a theme at all',
    );
    await tester.tap(find.byKey(const Key('terminal-theme-import-confirm')));
    await _flush(tester);

    expect(find.text(l10n.terminalThemeImportErrorFormat), findsOneWidget);
    expect(
      find.byKey(const Key('terminal-theme-import-confirm')),
      findsOneWidget,
    );
    expect(cubit.state.preferences.terminalThemeMode, 'adaptive');
    expect(Directory(themesDir).existsSync(), isFalse);
  });

  testWidgets('deleting the selected imported theme resets the mode', (
    tester,
  ) async {
    // Fixture setup touches the real filesystem, so it must run outside the
    // fake-async zone (see [_flush]). Reuses the importer so the stored shape
    // matches a real import.
    final saved = (await tester.runAsync(
      () => repo().save(_importFixture()!),
    ))!;
    final stored = (await tester.runAsync(() => repo().loadAll()))!;
    UserTerminalThemeRegistry.instance.replaceAll(stored);

    final cubit = await pumpCard(tester);
    cubit.setTerminalThemeMode(saved.id);
    await tester.pump();

    final deleteButton = find.byTooltip('Delete imported theme');
    await tester.ensureVisible(deleteButton);
    await tester.tap(deleteButton);
    await _flush(tester);

    await tester.tap(find.byKey(const Key('terminal-theme-delete-confirm')));
    await _flush(tester);

    expect(File(p.join(themesDir, '${saved.id}.json')).existsSync(), isFalse);
    expect(UserTerminalThemeRegistry.instance.themes, isEmpty);
    expect(cubit.state.preferences.terminalThemeMode, 'adaptive');

    await _drainToast(tester);
  });
}

/// Parses [_ghosttySource] through the real importer for the delete fixture.
CmuxTerminalTheme? _importFixture() =>
    importTerminalTheme(_ghosttySource, nameHint: 'Fixture Theme').theme;
