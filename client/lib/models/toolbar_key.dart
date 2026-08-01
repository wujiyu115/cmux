import 'package:flutter/foundation.dart';

/// Keys that mutate toolbar state instead of emitting bytes.
enum ToolbarKeySpecial { ctrl, alt, paste }

/// One key cap on the mobile terminal toolbar.
///
/// [label] is deliberately NOT localized: `^C` / `Esc` / `F1` / `/` are terminal
/// notation, identical in every locale. Group names ARE localized — see
/// `toolbarGroupLabel` in the toolbar UI.
@immutable
class ToolbarKey {
  const ToolbarKey({
    required this.id,
    required this.label,
    this.bytes = const [],
    this.special,
    this.repeatable = false,
  });

  final String id;
  final String label;
  final List<int> bytes;
  final ToolbarKeySpecial? special;

  /// Whether holding the key auto-repeats. Only arrows do (Nexterm parity),
  /// but this is declared per key rather than inferred from [id].
  final bool repeatable;
}

@immutable
class ToolbarKeyGroup {
  ToolbarKeyGroup({required this.id, required List<ToolbarKey> keys})
      : keys = List.unmodifiable(keys);

  final String id;

  /// Unmodifiable — callers must not reorder or mutate a group in place.
  final List<ToolbarKey> keys;
}

List<int> _char(String c) => c.codeUnits;

/// `^A`..`^_` — the caret notation maps to the character minus 0x40.
List<int> _ctrl(String c) => [c.toUpperCase().codeUnitAt(0) - 64];

List<int> _fKey(int n) {
  // F1–F4 are SS3-prefixed; F5–F12 are CSI <code> ~ with a non-contiguous
  // code table (xterm convention).
  if (n >= 1 && n <= 4) return [0x1b, 0x4f, 0x50 + n - 1];
  const codes = {
    5: '15', 6: '17', 7: '18', 8: '19',
    9: '20', 10: '21', 11: '23', 12: '24',
  };
  return [0x1b, 0x5b, ...codes[n]!.codeUnits, 0x7e];
}

const _esc = [0x1b];
const _tab = [0x09];
const _del = [0x1b, 0x5b, 0x33, 0x7e]; // CSI 3~
const _ins = [0x1b, 0x5b, 0x32, 0x7e]; // CSI 2~
const _home = [0x1b, 0x5b, 0x48]; // CSI H
const _end = [0x1b, 0x5b, 0x46]; // CSI F
const _pgUp = [0x1b, 0x5b, 0x35, 0x7e]; // CSI 5~
const _pgDn = [0x1b, 0x5b, 0x36, 0x7e]; // CSI 6~
const _up = [0x1b, 0x5b, 0x41];
const _down = [0x1b, 0x5b, 0x42];
const _right = [0x1b, 0x5b, 0x43];
const _left = [0x1b, 0x5b, 0x44];

/// How many groups the bar shows before customization.
const int defaultVisibleToolbarGroupCount = 4;

/// The 16 built-in groups, in default display order. Unmodifiable so the
/// lazily-built lookup maps below can never disagree with the live list.
final List<ToolbarKeyGroup> defaultToolbarGroups = List.unmodifiable([
  ToolbarKeyGroup(id: 'arrows', keys: [
    const ToolbarKey(
      id: 'arrow_left',
      label: '←',
      bytes: _left,
      repeatable: true,
    ),
    const ToolbarKey(id: 'arrow_up', label: '↑', bytes: _up, repeatable: true),
    const ToolbarKey(
      id: 'arrow_down',
      label: '↓',
      bytes: _down,
      repeatable: true,
    ),
    const ToolbarKey(
      id: 'arrow_right',
      label: '→',
      bytes: _right,
      repeatable: true,
    ),
  ]),
  ToolbarKeyGroup(id: 'clipboard', keys: [
    const ToolbarKey(
      id: 'paste',
      label: 'Paste',
      special: ToolbarKeySpecial.paste,
    ),
    ToolbarKey(id: 'ctrl_u', label: '^U', bytes: _ctrl('U')),
    ToolbarKey(id: 'ctrl_k', label: '^K', bytes: _ctrl('K')),
    ToolbarKey(id: 'ctrl_y', label: '^Y', bytes: _ctrl('Y')),
  ]),
  ToolbarKeyGroup(id: 'terminal_ctrl', keys: [
    const ToolbarKey(id: 'esc', label: 'Esc', bytes: _esc),
    const ToolbarKey(id: 'tab', label: 'Tab', bytes: _tab),
    const ToolbarKey(
      id: 'ctrl',
      label: 'Ctrl',
      special: ToolbarKeySpecial.ctrl,
    ),
    const ToolbarKey(id: 'alt', label: 'Alt', special: ToolbarKeySpecial.alt),
  ]),
  ToolbarKeyGroup(id: 'signals', keys: [
    ToolbarKey(id: 'ctrl_c', label: '^C', bytes: _ctrl('C')),
    ToolbarKey(id: 'ctrl_d', label: '^D', bytes: _ctrl('D')),
    ToolbarKey(id: 'ctrl_z', label: '^Z', bytes: _ctrl('Z')),
    ToolbarKey(id: 'ctrl_s', label: '^S', bytes: _ctrl('S')),
  ]),
  ToolbarKeyGroup(id: 'symbols1', keys: [
    ToolbarKey(id: 'slash', label: '/', bytes: _char('/')),
    ToolbarKey(id: 'pipe', label: '|', bytes: _char('|')),
    ToolbarKey(id: 'tilde', label: '~', bytes: _char('~')),
    ToolbarKey(id: 'dash', label: '-', bytes: _char('-')),
  ]),
  ToolbarKeyGroup(id: 'navigation', keys: [
    const ToolbarKey(id: 'home', label: 'Home', bytes: _home),
    const ToolbarKey(id: 'pgup', label: 'PgUp', bytes: _pgUp),
    const ToolbarKey(id: 'pgdn', label: 'PgDn', bytes: _pgDn),
    const ToolbarKey(id: 'end', label: 'End', bytes: _end),
  ]),
  ToolbarKeyGroup(id: 'editing', keys: [
    const ToolbarKey(id: 'del', label: 'Del', bytes: _del),
    const ToolbarKey(id: 'ins', label: 'Ins', bytes: _ins),
    ToolbarKey(id: 'at', label: '@', bytes: _char('@')),
    ToolbarKey(id: 'question', label: '?', bytes: _char('?')),
  ]),
  ToolbarKeyGroup(id: 'search', keys: [
    ToolbarKey(id: 'ctrl_r', label: '^R', bytes: _ctrl('R')),
    ToolbarKey(id: 'ctrl_g', label: '^G', bytes: _ctrl('G')),
    ToolbarKey(id: 'ctrl_n', label: '^N', bytes: _ctrl('N')),
    ToolbarKey(id: 'ctrl_p', label: '^P', bytes: _ctrl('P')),
  ]),
  ToolbarKeyGroup(id: 'punctuation', keys: [
    ToolbarKey(id: 'equals', label: '=', bytes: _char('=')),
    ToolbarKey(id: 'colon', label: ':', bytes: _char(':')),
    ToolbarKey(id: 'semicolon', label: ';', bytes: _char(';')),
    ToolbarKey(id: 'excl', label: '!', bytes: _char('!')),
  ]),
  ToolbarKeyGroup(id: 'symbols2', keys: [
    ToolbarKey(id: 'star', label: '*', bytes: _char('*')),
    ToolbarKey(id: 'dollar', label: r'$', bytes: _char(r'$')),
    ToolbarKey(id: 'percent', label: '%', bytes: _char('%')),
    ToolbarKey(id: 'caret', label: '^', bytes: _char('^')),
  ]),
  ToolbarKeyGroup(id: 'brackets1', keys: [
    ToolbarKey(id: 'lt', label: '<', bytes: _char('<')),
    ToolbarKey(id: 'gt', label: '>', bytes: _char('>')),
    ToolbarKey(id: 'lparen', label: '(', bytes: _char('(')),
    ToolbarKey(id: 'rparen', label: ')', bytes: _char(')')),
  ]),
  ToolbarKeyGroup(id: 'brackets2', keys: [
    ToolbarKey(id: 'lbrace', label: '{', bytes: _char('{')),
    ToolbarKey(id: 'rbrace', label: '}', bytes: _char('}')),
    ToolbarKey(id: 'lbracket', label: '[', bytes: _char('[')),
    ToolbarKey(id: 'rbracket', label: ']', bytes: _char(']')),
  ]),
  ToolbarKeyGroup(id: 'fkeys1', keys: [
    ToolbarKey(id: 'f1', label: 'F1', bytes: _fKey(1)),
    ToolbarKey(id: 'f2', label: 'F2', bytes: _fKey(2)),
    ToolbarKey(id: 'f3', label: 'F3', bytes: _fKey(3)),
    ToolbarKey(id: 'f4', label: 'F4', bytes: _fKey(4)),
  ]),
  ToolbarKeyGroup(id: 'fkeys2', keys: [
    ToolbarKey(id: 'f5', label: 'F5', bytes: _fKey(5)),
    ToolbarKey(id: 'f6', label: 'F6', bytes: _fKey(6)),
    ToolbarKey(id: 'f7', label: 'F7', bytes: _fKey(7)),
    ToolbarKey(id: 'f8', label: 'F8', bytes: _fKey(8)),
  ]),
  ToolbarKeyGroup(id: 'fkeys3', keys: [
    ToolbarKey(id: 'f9', label: 'F9', bytes: _fKey(9)),
    ToolbarKey(id: 'f10', label: 'F10', bytes: _fKey(10)),
    ToolbarKey(id: 'f11', label: 'F11', bytes: _fKey(11)),
    ToolbarKey(id: 'f12', label: 'F12', bytes: _fKey(12)),
  ]),
  ToolbarKeyGroup(id: 'advanced', keys: [
    ToolbarKey(id: 'ctrl_underscore', label: '^_', bytes: _ctrl('_')),
    ToolbarKey(id: 'ctrl_l', label: '^L', bytes: _ctrl('L')),
    const ToolbarKey(id: 'alt_r', label: 'Alt-r', bytes: [0x1b, 0x72]),
    const ToolbarKey(id: 'ctrl_x_x', label: '^X^X', bytes: [0x18, 0x18]),
  ]),
]);

List<String> get defaultToolbarGroupIds =>
    defaultToolbarGroups.map((g) => g.id).toList(growable: false);

final Map<String, ToolbarKeyGroup> _groupsById = {
  for (final g in defaultToolbarGroups) g.id: g,
};

final Map<String, ToolbarKey> _keysById = {
  for (final g in defaultToolbarGroups)
    for (final k in g.keys) k.id: k,
};

ToolbarKeyGroup? toolbarGroupById(String id) => _groupsById[id];

ToolbarKey? toolbarKeyById(String id) => _keysById[id];
