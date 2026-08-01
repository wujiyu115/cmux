import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/toolbar_key.dart';

/// Expected PTY bytes for every built-in key, grouped exactly as the defaults
/// are. Keep this table exhaustive: the coverage test below fails if any key in
/// [defaultToolbarGroups] is missing here.
const Map<String, Map<String, List<int>>> _expectedBytes = {
  'arrows': {
    'arrow_left': [0x1b, 0x5b, 0x44],
    'arrow_up': [0x1b, 0x5b, 0x41],
    'arrow_down': [0x1b, 0x5b, 0x42],
    'arrow_right': [0x1b, 0x5b, 0x43],
  },
  'clipboard': {
    'paste': [],
    'ctrl_u': [0x15],
    'ctrl_k': [0x0b],
    'ctrl_y': [0x19],
  },
  'terminal_ctrl': {
    'esc': [0x1b],
    'tab': [0x09],
    'ctrl': [],
    'alt': [],
  },
  'signals': {
    'ctrl_c': [0x03],
    'ctrl_d': [0x04],
    'ctrl_z': [0x1a],
    'ctrl_s': [0x13],
  },
  'symbols1': {
    'slash': [0x2f],
    'pipe': [0x7c],
    'tilde': [0x7e],
    'dash': [0x2d],
  },
  'navigation': {
    'home': [0x1b, 0x5b, 0x48],
    'pgup': [0x1b, 0x5b, 0x35, 0x7e],
    'pgdn': [0x1b, 0x5b, 0x36, 0x7e],
    'end': [0x1b, 0x5b, 0x46],
  },
  'editing': {
    'del': [0x1b, 0x5b, 0x33, 0x7e],
    'ins': [0x1b, 0x5b, 0x32, 0x7e],
    'at': [0x40],
    'question': [0x3f],
  },
  'search': {
    'ctrl_r': [0x12],
    'ctrl_g': [0x07],
    'ctrl_n': [0x0e],
    'ctrl_p': [0x10],
  },
  'punctuation': {
    'equals': [0x3d],
    'colon': [0x3a],
    'semicolon': [0x3b],
    'excl': [0x21],
  },
  'symbols2': {
    'star': [0x2a],
    'dollar': [0x24],
    'percent': [0x25],
    'caret': [0x5e],
  },
  'brackets1': {
    'lt': [0x3c],
    'gt': [0x3e],
    'lparen': [0x28],
    'rparen': [0x29],
  },
  'brackets2': {
    'lbrace': [0x7b],
    'rbrace': [0x7d],
    'lbracket': [0x5b],
    'rbracket': [0x5d],
  },
  'fkeys1': {
    'f1': [0x1b, 0x4f, 0x50],
    'f2': [0x1b, 0x4f, 0x51],
    'f3': [0x1b, 0x4f, 0x52],
    'f4': [0x1b, 0x4f, 0x53],
  },
  'fkeys2': {
    'f5': [0x1b, 0x5b, 0x31, 0x35, 0x7e],
    'f6': [0x1b, 0x5b, 0x31, 0x37, 0x7e],
    'f7': [0x1b, 0x5b, 0x31, 0x38, 0x7e],
    'f8': [0x1b, 0x5b, 0x31, 0x39, 0x7e],
  },
  'fkeys3': {
    'f9': [0x1b, 0x5b, 0x32, 0x30, 0x7e],
    'f10': [0x1b, 0x5b, 0x32, 0x31, 0x7e],
    'f11': [0x1b, 0x5b, 0x32, 0x33, 0x7e],
    'f12': [0x1b, 0x5b, 0x32, 0x34, 0x7e],
  },
  'advanced': {
    'ctrl_underscore': [0x1f],
    'ctrl_l': [0x0c],
    'alt_r': [0x1b, 0x72],
    'ctrl_x_x': [0x18, 0x18],
  },
};

void main() {
  test('16 groups of 4 keys, ids unique', () {
    expect(defaultToolbarGroups.length, 16);
    for (final g in defaultToolbarGroups) {
      expect(g.keys.length, 4, reason: 'group ${g.id} must have 4 keys');
    }
    final ids = defaultToolbarGroups.expand((g) => g.keys).map((k) => k.id);
    expect(ids.toSet().length, ids.length, reason: 'duplicate key id');
    expect(defaultToolbarGroupIds.first, 'arrows');
  });

  test('first four groups match the Nexterm default order', () {
    expect(
      defaultToolbarGroups.take(4).map((g) => g.id),
      ['arrows', 'clipboard', 'terminal_ctrl', 'signals'],
    );
  });

  group('every key carries the right bytes', () {
    for (final groupEntry in _expectedBytes.entries) {
      final groupId = groupEntry.key;
      test(groupId, () {
        final group = toolbarGroupById(groupId);
        expect(group, isNotNull, reason: 'missing group $groupId');
        expect(
          group!.keys.map((k) => k.id),
          groupEntry.value.keys,
          reason: '$groupId key ids or order changed',
        );
        for (final keyEntry in groupEntry.value.entries) {
          final key = toolbarKeyById(keyEntry.key);
          expect(key, isNotNull, reason: 'missing key ${keyEntry.key}');
          expect(
            key!.bytes,
            keyEntry.value,
            reason: 'wrong bytes for ${keyEntry.key}',
          );
        }
      });
    }
  });

  test('the byte table covers every key in the defaults', () {
    final expectedIds =
        _expectedBytes.values.expand((keys) => keys.keys).toSet();
    final actualIds =
        defaultToolbarGroups.expand((g) => g.keys).map((k) => k.id).toSet();
    expect(actualIds.length, 64);
    expect(
      actualIds.difference(expectedIds),
      isEmpty,
      reason: 'keys with no expected bytes in the table',
    );
    expect(
      expectedIds.difference(actualIds),
      isEmpty,
      reason: 'table lists keys that no longer exist',
    );
    expect(_expectedBytes.keys, defaultToolbarGroupIds);
  });

  test('special keys carry no bytes; only arrows repeat', () {
    expect(toolbarKeyById('ctrl')!.special, ToolbarKeySpecial.ctrl);
    expect(toolbarKeyById('alt')!.special, ToolbarKeySpecial.alt);
    expect(toolbarKeyById('paste')!.special, ToolbarKeySpecial.paste);
    for (final id in ['ctrl', 'alt', 'paste']) {
      expect(toolbarKeyById(id)!.bytes, isEmpty);
    }
    for (final key in defaultToolbarGroups.expand((g) => g.keys)) {
      if (!['ctrl', 'alt', 'paste'].contains(key.id)) {
        expect(key.special, isNull, reason: '${key.id} must not be special');
      }
    }
    expect(toolbarKeyById('arrow_down')!.repeatable, isTrue);
    expect(toolbarKeyById('ctrl_c')!.repeatable, isFalse);
    for (final key in defaultToolbarGroups.expand((g) => g.keys)) {
      expect(
        key.repeatable,
        key.id.startsWith('arrow_'),
        reason: 'unexpected repeatable for ${key.id}',
      );
    }
    expect(toolbarKeyById('nope'), isNull);
  });

  test('defaults are unmodifiable', () {
    expect(
      () => defaultToolbarGroups.add(
        ToolbarKeyGroup(id: 'x', keys: const []),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => defaultToolbarGroups.first.keys.clear(),
      throwsUnsupportedError,
    );
  });
}
