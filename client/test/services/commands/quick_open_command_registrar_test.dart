import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/quick_open_command_registrar.dart';

void main() {
  test('open invokes the bound opener', () {
    final bus = CommandBus();
    final host = QuickOpenHost();
    registerQuickOpenCommands(bus, host);

    var opened = 0;
    host.bind(() => opened++);
    bus.invoke(CommandIds.quickOpen);
    expect(opened, 1);
  });

  test('unbind stops invocation', () {
    final bus = CommandBus();
    final host = QuickOpenHost();
    registerQuickOpenCommands(bus, host);

    var opened = 0;
    void opener() => opened++;
    host.bind(opener);
    host.unbind(opener);
    bus.invoke(CommandIds.quickOpen);
    expect(opened, 0);
  });

  test('no opener bound is a silent no-op', () {
    final bus = CommandBus();
    final host = QuickOpenHost();
    registerQuickOpenCommands(bus, host);
    bus.invoke(CommandIds.quickOpen); // must not throw
  });
}
