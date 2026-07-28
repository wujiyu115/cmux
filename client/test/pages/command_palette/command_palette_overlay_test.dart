import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/shortcut_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/command_palette/command_palette_overlay.dart';
import 'package:teampilot/repositories/command_mru_repository.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/shortcut_context.dart';

import '../../support/in_memory_filesystem.dart';

Widget _wrap(Widget child, {required ShortcutCubit shortcutCubit}) {
  final theme = ThemeData(useMaterial3: true);
  // Provider + TpTheme sit above MaterialApp so root-navigator dialogs (the
  // palette is shown via showDialog) can still resolve them.
  return BlocProvider<ShortcutCubit>.value(
    value: shortcutCubit,
    child: TpTheme(
      data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: theme,
        home: Scaffold(body: child),
      ),
    ),
  );
}

CommandMruRepository _mru() =>
    CommandMruRepository(fs: InMemoryFilesystem(), path: '/command-mru.json');

void main() {
  testWidgets('renders only available commands (when + handler)', (
    tester,
  ) async {
    final bus = CommandBus();
    bus.register(CommandIds.zoomIn, () {});
    bus.register(CommandIds.toggleSidebar, () {});
    // zoomOut intentionally has no handler → must not be listed.

    await tester.pumpWidget(
      _wrap(
        CommandPaletteOverlay(
          bus: bus,
          mru: const [],
          shortcutContext: const ShortcutContext(hasWorkspace: true),
        ),
        shortcutCubit: ShortcutCubit(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Zoom In'), findsOneWidget);
    expect(find.text('Toggle Sidebar'), findsOneWidget);
    expect(find.text('Zoom Out'), findsNothing);
  });

  testWidgets('typing filters the list', (tester) async {
    final bus = CommandBus();
    bus.register(CommandIds.zoomIn, () {});
    bus.register(CommandIds.toggleSidebar, () {});

    await tester.pumpWidget(
      _wrap(
        CommandPaletteOverlay(
          bus: bus,
          mru: const [],
          shortcutContext: const ShortcutContext(hasWorkspace: true),
        ),
        shortcutCubit: ShortcutCubit(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'sidebar');
    await tester.pumpAndSettle();

    expect(find.text('Toggle Sidebar'), findsOneWidget);
    expect(find.text('Zoom In'), findsNothing);
  });

  testWidgets('chord badge text is shown for a bound command', (tester) async {
    final bus = CommandBus();
    bus.register(CommandIds.zoomIn, () {});

    await tester.pumpWidget(
      _wrap(
        CommandPaletteOverlay(
          bus: bus,
          mru: const [],
          shortcutContext: const ShortcutContext(hasWorkspace: true),
        ),
        shortcutCubit: ShortcutCubit(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zoom in');
    await tester.pumpAndSettle();

    // zoomIn default chord is Mod+= → "Ctrl+=" off macOS.
    expect(find.text('Ctrl+='), findsOneWidget);
  });

  testWidgets('down + Enter invokes the selected command through the bus', (
    tester,
  ) async {
    final invoked = <String>[];
    final bus = CommandBus();
    bus.register(CommandIds.zoomIn, () => invoked.add(CommandIds.zoomIn));
    bus.register(CommandIds.zoomOut, () => invoked.add(CommandIds.zoomOut));
    bus.register(CommandIds.zoomReset, () => invoked.add(CommandIds.zoomReset));

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showCommandPalette(
              context,
              bus: bus,
              mruRepository: _mru(),
              shortcutContext: const ShortcutContext(hasWorkspace: true),
            ),
            child: const Text('open'),
          ),
        ),
        shortcutCubit: ShortcutCubit(),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zoom');
    await tester.pumpAndSettle();

    // Catalog order: zoomIn, zoomOut, zoomReset → down once selects zoomOut.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(invoked, [CommandIds.zoomOut]);
    expect(find.byType(CommandPaletteOverlay), findsNothing);
  });

  testWidgets('Esc closes without invoking', (tester) async {
    final invoked = <String>[];
    final bus = CommandBus();
    bus.register(CommandIds.zoomIn, () => invoked.add(CommandIds.zoomIn));

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showCommandPalette(
              context,
              bus: bus,
              mruRepository: _mru(),
              shortcutContext: const ShortcutContext(hasWorkspace: true),
            ),
            child: const Text('open'),
          ),
        ),
        shortcutCubit: ShortcutCubit(),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(CommandPaletteOverlay), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(CommandPaletteOverlay), findsNothing);
    expect(invoked, isEmpty);
  });
}
