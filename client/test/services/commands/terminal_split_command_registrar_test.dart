import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/terminal_split.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/terminal_split_command_registrar.dart';
import 'package:teampilot/services/terminal/terminal_layout_presets.dart';

class _FakeHost implements TerminalSplitCommandHost {
  final List<String> calls = [];
  final List<PaneDirection> directions = [];
  final List<TerminalLayoutPreset> presets = [];

  @override
  void splitRight() => calls.add('splitRight');
  @override
  void splitDown() => calls.add('splitDown');
  @override
  void focusNextPane() => calls.add('focusNextPane');
  @override
  void focusPrevPane() => calls.add('focusPrevPane');
  @override
  void focusPaneInDirection(PaneDirection direction) {
    calls.add('focusPaneInDirection');
    directions.add(direction);
  }

  @override
  void toggleZoom() => calls.add('toggleZoom');
  @override
  void equalizePanes() => calls.add('equalizePanes');
  @override
  void closeActivePane() => calls.add('closeActivePane');
  @override
  void applyLayoutPreset(TerminalLayoutPreset preset) {
    calls.add('applyLayoutPreset');
    presets.add(preset);
  }

  @override
  void showCommandLog() => calls.add('showCommandLog');
}

void main() {
  late CommandBus bus;
  late _FakeHost host;
  late VoidCallback disposer;

  setUp(() {
    bus = CommandBus();
    host = _FakeHost();
    disposer = registerTerminalSplitCommands(bus, host);
  });

  test('split commands invoke the matching host method', () {
    bus.invoke(CommandIds.terminalSplitRight);
    bus.invoke(CommandIds.terminalSplitDown);
    expect(host.calls, ['splitRight', 'splitDown']);
  });

  test('linear focus commands invoke next/prev', () {
    bus.invoke(CommandIds.terminalPaneFocusNext);
    bus.invoke(CommandIds.terminalPaneFocusPrev);
    expect(host.calls, ['focusNextPane', 'focusPrevPane']);
  });

  test('directional focus commands pass the right PaneDirection', () {
    bus.invoke(CommandIds.terminalPaneFocusLeft);
    bus.invoke(CommandIds.terminalPaneFocusRight);
    bus.invoke(CommandIds.terminalPaneFocusUp);
    bus.invoke(CommandIds.terminalPaneFocusDown);
    expect(host.directions, [
      PaneDirection.left,
      PaneDirection.right,
      PaneDirection.up,
      PaneDirection.down,
    ]);
  });

  test('zoom / equalize / close invoke their host methods', () {
    bus.invoke(CommandIds.terminalPaneZoom);
    bus.invoke(CommandIds.terminalPaneEqualize);
    bus.invoke(CommandIds.terminalPaneClose);
    expect(host.calls, ['toggleZoom', 'equalizePanes', 'closeActivePane']);
  });

  test('layout commands map to the right presets', () {
    bus.invoke(CommandIds.terminalLayoutSingle);
    bus.invoke(CommandIds.terminalLayoutColumns2);
    bus.invoke(CommandIds.terminalLayoutColumns3);
    bus.invoke(CommandIds.terminalLayoutGrid);
    bus.invoke(CommandIds.terminalLayoutMainStack);
    expect(host.presets, [
      TerminalLayoutPreset.single,
      TerminalLayoutPreset.columns2,
      TerminalLayoutPreset.columns3,
      TerminalLayoutPreset.grid2x2,
      TerminalLayoutPreset.mainStack,
    ]);
  });

  test('command log command reaches the host', () {
    bus.invoke(CommandIds.terminalCommandLog);
    expect(host.calls, ['showCommandLog']);
  });

  test('disposer unregisters exactly its handlers', () {
    disposer();
    bus.invoke(CommandIds.terminalSplitRight);
    bus.invoke(CommandIds.terminalPaneFocusLeft);
    bus.invoke(CommandIds.terminalLayoutGrid);
    expect(host.calls, isEmpty);
  });

  test('disposer is identity-guarded and does not clobber a newer claim', () {
    final second = _FakeHost();
    registerTerminalSplitCommands(bus, second);
    // The first registrar's disposer must not remove the second's handler.
    disposer();
    bus.invoke(CommandIds.terminalSplitRight);
    expect(host.calls, isEmpty);
    expect(second.calls, ['splitRight']);
  });
}
