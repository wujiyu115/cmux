import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/content_find_command_registrar.dart';

void main() {
  test('claim routes Mod+F to the claimed surface', () {
    final bus = CommandBus();
    var opened = 0;
    final dispose = claimContentFindCommand(bus, () => opened++);

    bus.invoke(CommandIds.contentFind);
    expect(opened, 1);

    dispose();
    bus.invoke(CommandIds.contentFind);
    expect(opened, 1);
  });

  test('last claim wins while both are held', () {
    final bus = CommandBus();
    var first = 0;
    var second = 0;
    final disposeFirst = claimContentFindCommand(bus, () => first++);
    final disposeSecond = claimContentFindCommand(bus, () => second++);

    bus.invoke(CommandIds.contentFind);
    expect(first, 0);
    expect(second, 1);

    disposeFirst();
    disposeSecond();
  });

  test('a stale disposer never clobbers a newer claim', () {
    final bus = CommandBus();
    var first = 0;
    var second = 0;
    final disposeFirst = claimContentFindCommand(bus, () => first++);
    disposeFirst();
    final disposeSecond = claimContentFindCommand(bus, () => second++);

    // Focus can race: terminal A blurs (stale disposeFirst runs) after
    // terminal B already claimed. B's claim must survive.
    disposeFirst();

    bus.invoke(CommandIds.contentFind);
    expect(first, 0);
    expect(second, 1);

    disposeSecond();
  });
}
