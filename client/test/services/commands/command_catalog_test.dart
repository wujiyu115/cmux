import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/commands/command_catalog.dart';
import 'package:teampilot/services/commands/command_definition.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/command_l10n.dart';
import 'package:teampilot/services/commands/key_chord.dart';
import 'package:teampilot/services/commands/key_chord_formatter.dart';
import 'package:teampilot/services/commands/keybinding_resolver.dart';

void main() {
  test('v1 catalog contains required command ids', () {
    final ids = CommandCatalog.v1.map((c) => c.id).toSet();
    expect(ids, containsAll([
      CommandIds.workspaceNextTab,
      CommandIds.workspaceSearch,
      CommandIds.stripNextTab,
      CommandIds.sessionCloseTab,
      CommandIds.zoomIn,
      CommandIds.composeSubmit,
      CommandIds.showCheatsheet,
      CommandIds.toggleSidebar,
    ]));
  });

  test('workspace search defaults to Mod+F and double Shift', () {
    final def = CommandCatalog.v1.singleWhere(
      (c) => c.id == CommandIds.workspaceSearch,
    );
    expect(def.defaultChords, [
      KeyChord(key: 'f', mods: [KeyChordMod.mod]),
      KeyChord.doubleTapShift(),
    ]);
    expect(def.when, ShortcutWhen.hasWorkspace);
    expect(def.terminalPassthrough, isTrue);
  });

  test('strip next tab defaults to explicit ctrl+tab', () {
    final def = CommandCatalog.v1.singleWhere(
      (c) => c.id == CommandIds.stripNextTab,
    );
    expect(def.defaultChords, [
      KeyChord(key: 'tab', mods: [KeyChordMod.ctrl]),
    ]);
    expect(def.terminalPassthrough, isTrue);
  });

  test('compose submit is unmodified enter, not passthrough', () {
    final def = CommandCatalog.v1.singleWhere(
      (c) => c.id == CommandIds.composeSubmit,
    );
    expect(def.defaultChords, [KeyChord(key: 'enter')]);
    expect(def.terminalPassthrough, isFalse);
    expect(def.when, ShortcutWhen.inCompose);
  });

  test('Alt+1…9 / Alt+0 focus strip tabs by ordinal', () {
    for (var n = 1; n <= 10; n++) {
      final def = CommandCatalog.v1.singleWhere(
        (c) => c.id == CommandIds.stripFocusTab(n),
      );
      expect(
        def.defaultChords,
        [
          KeyChord(
            key: n == 10 ? 'digit0' : 'digit$n',
            mods: [KeyChordMod.alt],
          ),
        ],
      );
      expect(def.when, ShortcutWhen.hasWorkspace);
      expect(def.terminalPassthrough, isTrue);
    }
  });

  test('catalog default bindings have zero keychord conflicts', () {
    final conflicts = KeybindingResolver.findConflicts(
      KeybindingResolver.effectiveBindings(
        catalog: CommandCatalog.v1,
        overrides: const {},
      ),
    );
    expect(
      conflicts,
      isEmpty,
      reason: conflicts
          .map(
            (c) =>
                '${formatKeyChord(c.chord, isMacOS: false)} -> '
                '${c.commandIds.join(", ")}',
          )
          .join('; '),
    );
  });

  test('every terminal-pane command is terminalPassthrough', () {
    const terminalIds = {
      CommandIds.terminalSplitRight,
      CommandIds.terminalSplitDown,
      CommandIds.terminalPaneFocusNext,
      CommandIds.terminalPaneFocusPrev,
      CommandIds.terminalPaneFocusLeft,
      CommandIds.terminalPaneFocusRight,
      CommandIds.terminalPaneFocusUp,
      CommandIds.terminalPaneFocusDown,
      CommandIds.terminalPaneZoom,
      CommandIds.terminalPaneEqualize,
      CommandIds.terminalPaneClose,
      CommandIds.terminalLayoutSingle,
      CommandIds.terminalLayoutColumns2,
      CommandIds.terminalLayoutColumns3,
      CommandIds.terminalLayoutGrid,
      CommandIds.terminalLayoutMainStack,
      CommandIds.terminalCommandLog,
      CommandIds.terminalCommandHistory,
    };
    for (final id in terminalIds) {
      final def = CommandCatalog.v1.singleWhere((c) => c.id == id);
      expect(def.terminalPassthrough, isTrue, reason: id);
      expect(def.category, CommandCategory.terminal, reason: id);
      expect(def.when, ShortcutWhen.hasWorkspace, reason: id);
    }
  });

  test('command palette definition reserves Mod+Shift+P (meta, always)', () {
    final def = CommandCatalog.v1.singleWhere(
      (c) => c.id == CommandIds.commandPalette,
    );
    expect(def.defaultChords, [
      KeyChord(key: 'p', mods: [KeyChordMod.mod, KeyChordMod.shift]),
    ]);
    expect(def.category, CommandCategory.meta);
    expect(def.when, ShortcutWhen.always);
  });

  test('every catalog title and category resolves to a non-empty l10n string', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    for (final def in CommandCatalog.v1) {
      final title = titleForCommand(l10n, def.id);
      expect(title, isNotEmpty, reason: def.id);
      // titleForCommand returns the id unchanged only on catalog/ARB drift.
      expect(title, isNot(def.id), reason: def.id);
      expect(titleForCategory(l10n, def.category), isNotEmpty, reason: def.id);
    }
  });
}
