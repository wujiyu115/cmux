import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/toolbar_key.dart';

void main() {
  test('16 groups of 4 keys, ids unique', () {
    expect(defaultToolbarGroups.length, 16);
    for (final g in defaultToolbarGroups) {
      expect(g.keys.length, 4, reason: 'group ${g.id} must have 4 keys');
    }
    final ids = defaultToolbarGroups.expand((g) => g.keys).map((k) => k.id);
    expect(ids.toSet().length, ids.length, reason: 'duplicate key id');
    expect(defaultToolbarGroupIds.first, 'arrows');
    expect(defaultVisibleToolbarGroupCount, 4);
  });

  test('first four groups match the Nexterm default order', () {
    expect(
      defaultToolbarGroups.take(4).map((g) => g.id),
      ['arrows', 'clipboard', 'terminal_ctrl', 'signals'],
    );
  });

  test('control codes, escape sequences and F-keys carry the right bytes', () {
    expect(toolbarKeyById('ctrl_c')!.bytes, [0x03]);
    expect(toolbarKeyById('ctrl_underscore')!.bytes, [0x1f]);
    expect(toolbarKeyById('esc')!.bytes, [0x1b]);
    expect(toolbarKeyById('tab')!.bytes, [0x09]);
    expect(toolbarKeyById('arrow_left')!.bytes, [0x1b, 0x5b, 0x44]);
    expect(toolbarKeyById('arrow_up')!.bytes, [0x1b, 0x5b, 0x41]);
    expect(toolbarKeyById('home')!.bytes, [0x1b, 0x5b, 0x48]);
    expect(toolbarKeyById('pgup')!.bytes, [0x1b, 0x5b, 0x35, 0x7e]);
    expect(toolbarKeyById('del')!.bytes, [0x1b, 0x5b, 0x33, 0x7e]);
    expect(toolbarKeyById('f1')!.bytes, [0x1b, 0x4f, 0x50]);
    expect(toolbarKeyById('f4')!.bytes, [0x1b, 0x4f, 0x53]);
    expect(toolbarKeyById('f5')!.bytes, [0x1b, 0x5b, 0x31, 0x35, 0x7e]);
    expect(toolbarKeyById('f12')!.bytes, [0x1b, 0x5b, 0x32, 0x34, 0x7e]);
    expect(toolbarKeyById('alt_r')!.bytes, [0x1b, 0x72]);
    expect(toolbarKeyById('ctrl_x_x')!.bytes, [0x18, 0x18]);
    expect(toolbarKeyById('slash')!.bytes, [0x2f]);
  });

  test('special keys carry no bytes; only arrows repeat', () {
    expect(toolbarKeyById('ctrl')!.special, ToolbarKeySpecial.ctrl);
    expect(toolbarKeyById('alt')!.special, ToolbarKeySpecial.alt);
    expect(toolbarKeyById('paste')!.special, ToolbarKeySpecial.paste);
    for (final id in ['ctrl', 'alt', 'paste']) {
      expect(toolbarKeyById(id)!.bytes, isEmpty);
    }
    expect(toolbarKeyById('arrow_down')!.repeatable, isTrue);
    expect(toolbarKeyById('ctrl_c')!.repeatable, isFalse);
    expect(toolbarKeyById('nope'), isNull);
  });
}
