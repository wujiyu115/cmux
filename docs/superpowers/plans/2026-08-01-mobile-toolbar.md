# Mobile Terminal Shortcut Toolbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the cmux mobile pairing mirror a 44px shortcut-key toolbar (16 key groups, one-shot Ctrl/Alt, arrow auto-repeat, reorderable customize page, usage counters), ported from Nexterm.

**Architecture:** Four layers with hard boundaries — a pure data layer (`ToolbarKey` / `defaultToolbarGroups`), a pure encoder (`encodeToolbarKey`), a `flutter_bloc` cubit that owns modifier state plus persisted layout via a `shared_preferences` repository, and route-only UI under `client/lib/pages/pairing/mobile_toolbar/`. The cubit receives `void Function(List<int>) sendInput` by injection, so it never learns about pairing; the mirror page passes `PairingClientCubit.sendInput`.

**Tech Stack:** Flutter 3.29 / Dart 3, `flutter_bloc`, `shared_preferences ^2.5.3`, `flutter_test` + `fake_async ^1.3.1` (no `bloc_test` in this repo — do not add it).

**Spec:** `docs/superpowers/specs/2026-08-01-mobile-toolbar-design.md`

## Global Constraints

- Work from `/Users/yitouxiaomaolv/git/cmux/client`. All `flutter` commands run there.
- Gate before claiming any task done: `flutter analyze --no-fatal-infos --no-fatal-warnings` and `flutter test --exclude-tags integration`.
- Two pre-existing test failures are NOT yours and must not be "fixed": `test/pages/command_palette/command_palette_overlay_test.dart` (chord badge) and `test/services/terminal/pty_launch_environment_test.dart` (TERM_PROGRAM). Everything else must pass.
- State management is `flutter_bloc` only. Never `provider`, never `setState` for cross-widget state.
- All user-facing strings go in BOTH `lib/l10n/app_en.arb` and `lib/l10n/app_zh.arb`, referenced via `context.l10n.<key>`. Key-cap labels (`^C`, `Esc`, `F1`, `/`) are data, NOT l10n.
- After any ARB change run `dart run tool/gen_warmup_glyphs.dart`.
- No `print`; diagnostics go through `AppLogger`.
- Widget tests that render localized UI must wrap `MaterialApp` with `AppLocalizations.localizationsDelegates` + `supportedLocales` + `locale: const Locale('en')`.
- Widget test keys live in `lib/utils/ui/app_keys.dart` as `static const x = Key('kebab-name')`.
- File size soft caps: cubits ~500 lines, services ~600, page shells ~400.
- Colors come from `Theme.of(context).colorScheme` — this repo has no palette extension with `accent`/`border`/`fg` names.
- Commit after every task with the exact message given in the task's final step.

## File Structure

| File | Responsibility |
|---|---|
| `lib/models/toolbar_key.dart` (create) | `ToolbarKey`, `ToolbarKeyGroup`, `ToolbarKeySpecial`, the 16 default groups, `defaultVisibleToolbarGroupCount`, `toolbarKeyById` lookup. No Flutter widgets, no IO. |
| `lib/services/terminal/toolbar_key_encoder.dart` (create) | `encodeToolbarKey(bytes, ctrl:, alt:)` + `terminalizeNewlines(text)`. Pure. |
| `lib/repositories/mobile_toolbar_repository.dart` (create) | `MobileToolbarPrefs`, abstract repo, `SharedPrefs…` + `InMemory…` impls, `sanitizeToolbarPrefs`. |
| `lib/cubits/mobile_toolbar_cubit.dart` (create) | `MobileToolbarState` + `MobileToolbarCubit`: modifier state, tap dispatch, usage debounce, layout mutation. |
| `lib/pages/pairing/mobile_toolbar/mobile_keyboard_toolbar.dart` (create) | The 44px bar: horizontal key strip + fixed hide-keyboard button; `_ToolbarKeyButton` owns long-press repeat. |
| `lib/pages/pairing/mobile_toolbar/mobile_toolbar_customize_page.dart` (create) | Reorder groups, set visible count, show most-used, reset. |
| `lib/pages/pairing/pairing_mirror_page.dart` (modify `:111-181`) | Provide the cubit, swap `_MirrorBar` for the toolbar, delete `_MirrorBar`. |
| `lib/pages/pairing/mobile_toolbar/mobile_toolbar_labels.dart` (create) | `toolbarGroupLabel(id, l10n)` — the only place group ids meet localized names. |
| `lib/utils/ui/app_keys.dart` (modify, after `:72`) | New toolbar keys. |
| `lib/l10n/app_en.arb`, `app_zh.arb` (modify) | 16 group names + customize page strings + hide-keyboard tooltip; retire `pairingMirrorInputHint`. |

---

### Task 1: Toolbar key data model

**Files:**
- Create: `client/lib/models/toolbar_key.dart`
- Test: `client/test/models/toolbar_key_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum ToolbarKeySpecial { ctrl, alt, paste }`; `class ToolbarKey { String id; String label; List<int> bytes; ToolbarKeySpecial? special; bool get repeatable; }`; `class ToolbarKeyGroup { String id; List<ToolbarKey> keys; }`; `List<ToolbarKeyGroup> get defaultToolbarGroups`; `const int defaultVisibleToolbarGroupCount = 4`; `List<String> get defaultToolbarGroupIds`; `ToolbarKey? toolbarKeyById(String id)`; `ToolbarKeyGroup? toolbarGroupById(String id)`.

- [ ] **Step 1: Write the failing test**

Create `client/test/models/toolbar_key_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/toolbar_key_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'teampilot' … toolbar_key.dart` / `Method not found: 'toolbarKeyById'`.

- [ ] **Step 3: Write the implementation**

Create `client/lib/models/toolbar_key.dart`:

```dart
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
  });

  final String id;
  final String label;
  final List<int> bytes;
  final ToolbarKeySpecial? special;

  /// Arrow keys auto-repeat while held; nothing else does (Nexterm parity).
  bool get repeatable => id.startsWith('arrow_');
}

@immutable
class ToolbarKeyGroup {
  const ToolbarKeyGroup({required this.id, required this.keys});

  final String id;
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

/// The 16 built-in groups, in default display order.
final List<ToolbarKeyGroup> defaultToolbarGroups = [
  ToolbarKeyGroup(id: 'arrows', keys: [
    const ToolbarKey(id: 'arrow_left', label: '←', bytes: _left),
    const ToolbarKey(id: 'arrow_up', label: '↑', bytes: _up),
    const ToolbarKey(id: 'arrow_down', label: '↓', bytes: _down),
    const ToolbarKey(id: 'arrow_right', label: '→', bytes: _right),
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
];

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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/models/toolbar_key_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/yitouxiaomaolv/git/cmux
git add client/lib/models/toolbar_key.dart client/test/models/toolbar_key_test.dart
git commit -m "feat(mobile): add terminal toolbar key definitions"
```

---

### Task 2: Key encoder (Ctrl/Alt + newline normalization)

**Files:**
- Create: `client/lib/services/terminal/toolbar_key_encoder.dart`
- Test: `client/test/services/terminal/toolbar_key_encoder_test.dart`

**Interfaces:**
- Consumes: nothing (operates on raw `List<int>`).
- Produces: `List<int> encodeToolbarKey(List<int> bytes, {bool ctrl = false, bool alt = false})`; `String terminalizeNewlines(String text)`.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/terminal/toolbar_key_encoder_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/toolbar_key_encoder.dart';

void main() {
  group('no modifier', () {
    test('passes bytes through untouched', () {
      expect(encodeToolbarKey([0x2f]), [0x2f]);
      expect(encodeToolbarKey([0x1b, 0x5b, 0x41]), [0x1b, 0x5b, 0x41]);
      expect(encodeToolbarKey(const []), isEmpty);
    });
  });

  group('ctrl', () {
    test('maps a printable byte into its control code', () {
      expect(encodeToolbarKey([0x61], ctrl: true), [0x01]); // ^A
      expect(encodeToolbarKey([0x40], ctrl: true), [0x00]); // ^@
      expect(encodeToolbarKey([0x7f], ctrl: true), [0x1f]);
    });

    test('leaves bytes outside 0x40..0x7f alone', () {
      expect(encodeToolbarKey([0x09], ctrl: true), [0x09]); // Tab
      expect(encodeToolbarKey([0x1b], ctrl: true), [0x1b]); // Esc
    });

    test('rewrites escape sequences with xterm modifier 5', () {
      expect(
        encodeToolbarKey([0x1b, 0x5b, 0x41], ctrl: true),
        [0x1b, 0x5b, 0x31, 0x3b, 0x35, 0x41], // CSI 1;5 A
      );
      expect(
        encodeToolbarKey([0x1b, 0x4f, 0x50], ctrl: true),
        [0x1b, 0x5b, 0x31, 0x3b, 0x35, 0x50], // F1 → CSI 1;5 P
      );
      expect(
        encodeToolbarKey([0x1b, 0x5b, 0x35, 0x7e], ctrl: true),
        [0x1b, 0x5b, 0x35, 0x3b, 0x35, 0x7e], // CSI 5;5 ~
      );
    });

    test('leaves a non-escape multi-byte key alone', () {
      expect(encodeToolbarKey([0x18, 0x18], ctrl: true), [0x18, 0x18]);
    });
  });

  group('alt', () {
    test('prefixes a single byte with ESC', () {
      expect(encodeToolbarKey([0x2f], alt: true), [0x1b, 0x2f]);
    });

    test('rewrites escape sequences with xterm modifier 3', () {
      expect(
        encodeToolbarKey([0x1b, 0x4f, 0x50], alt: true),
        [0x1b, 0x5b, 0x31, 0x3b, 0x33, 0x50],
      );
      expect(
        encodeToolbarKey([0x1b, 0x5b, 0x35, 0x7e], alt: true),
        [0x1b, 0x5b, 0x35, 0x3b, 0x33, 0x7e],
      );
    });
  });

  test('ctrl wins when both modifiers are somehow set', () {
    expect(encodeToolbarKey([0x61], ctrl: true, alt: true), [0x01]);
  });

  test('unrecognised escape shapes are returned unchanged', () {
    // CSI 200 h — parameterised but not a "~"-terminated key.
    const raw = [0x1b, 0x5b, 0x32, 0x30, 0x30, 0x68];
    expect(encodeToolbarKey(raw, ctrl: true), raw);
  });

  group('terminalizeNewlines', () {
    test('turns LF and CRLF into CR so the shell submits', () {
      expect(terminalizeNewlines('a\nb'), 'a\rb');
      expect(terminalizeNewlines('a\r\nb'), 'a\rb');
      expect(terminalizeNewlines('plain'), 'plain');
      expect(terminalizeNewlines('trailing\n'), 'trailing\r');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/terminal/toolbar_key_encoder_test.dart`
Expected: FAIL — `Error: Method not found: 'encodeToolbarKey'`.

- [ ] **Step 3: Write the implementation**

Create `client/lib/services/terminal/toolbar_key_encoder.dart`:

```dart
/// Applies the toolbar's one-shot Ctrl / Alt modifiers to a key's bytes.
///
/// Single bytes follow the terminal conventions every shell expects: Ctrl masks
/// to the control range, Alt sends an ESC prefix (8-bit meta is never used).
/// Multi-byte escape sequences instead get the xterm *modifier parameter* — 5
/// for Ctrl, 3 for Alt — because `ESC` + `CSI A` is not "Ctrl+Up" to anything.
///
/// [ctrl] takes precedence if both are set; the cubit keeps them mutually
/// exclusive, so that only guards against a caller mistake.
List<int> encodeToolbarKey(
  List<int> bytes, {
  bool ctrl = false,
  bool alt = false,
}) {
  if (bytes.isEmpty) return const [];
  if (ctrl) {
    if (bytes.length == 1) {
      final code = bytes.first;
      // Only the 0x40..0x7f band has a control-code equivalent; Tab / Esc and
      // friends are already control codes and must pass through untouched.
      return (code >= 0x40 && code <= 0x7f) ? [code & 0x1f] : bytes;
    }
    return _applyEscModifier(bytes, 5);
  }
  if (alt) {
    if (bytes.length == 1) return [0x1b, ...bytes];
    return _applyEscModifier(bytes, 3);
  }
  return bytes;
}

/// Rewrites an escape sequence to carry an xterm modifier parameter.
///
///   `ESC O P`   → `CSI 1;<m> P`   (SS3 function keys)
///   `CSI A`     → `CSI 1;<m> A`   (arrows, Home, End)
///   `CSI 5 ~`   → `CSI 5;<m> ~`   (PgUp, Del, F5+)
///
/// Anything else is returned as-is: a mangled sequence is worse than an
/// unmodified one.
List<int> _applyEscModifier(List<int> bytes, int modifier) {
  if (bytes.length < 3 || bytes.first != 0x1b) return bytes;
  final m = modifier.toString().codeUnits;
  const csi = [0x1b, 0x5b];
  if (bytes[1] == 0x4f && bytes.length == 3) {
    return [...csi, 0x31, 0x3b, ...m, bytes[2]];
  }
  if (bytes[1] != 0x5b) return bytes;
  if (bytes.length == 3) return [...csi, 0x31, 0x3b, ...m, bytes[2]];
  if (bytes.last == 0x7e) {
    final params = bytes.sublist(2, bytes.length - 1);
    final numeric =
        params.isNotEmpty && params.every((b) => b >= 0x30 && b <= 0x39);
    if (numeric) return [...csi, ...params, 0x3b, ...m, 0x7e];
  }
  return bytes;
}

/// Rewrites newlines to CR for PTY submission.
///
/// A PTY's line discipline maps CR→NL on input but never NL→CR, so a pasted
/// `\n` leaves readline and TUIs waiting instead of running the line. Same
/// convention as `ImeSession` in flutter_alacritty.
String terminalizeNewlines(String text) =>
    text.replaceAll('\r\n', '\r').replaceAll('\n', '\r');
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/terminal/toolbar_key_encoder_test.dart`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/yitouxiaomaolv/git/cmux
git add client/lib/services/terminal/toolbar_key_encoder.dart client/test/services/terminal/toolbar_key_encoder_test.dart
git commit -m "feat(mobile): encode toolbar Ctrl/Alt into terminal byte sequences"
```

---

### Task 3: Layout persistence repository

**Files:**
- Create: `client/lib/repositories/mobile_toolbar_repository.dart`
- Test: `client/test/repositories/mobile_toolbar_repository_test.dart`

**Interfaces:**
- Consumes: `defaultToolbarGroupIds`, `defaultVisibleToolbarGroupCount`, `toolbarKeyById` (Task 1).
- Produces: `class MobileToolbarPrefs { List<String> groupOrder; int visibleGroupCount; Map<String,int> usage; MobileToolbarPrefs copyWith({...}); Map<String,Object?> toJson(); }`; `MobileToolbarPrefs sanitizeToolbarPrefs({Iterable<String>? groupOrder, int? visibleGroupCount, Map<String,int>? usage})`; `abstract class MobileToolbarRepository { Future<MobileToolbarPrefs> load(); Future<void> save(MobileToolbarPrefs prefs); }`; `SharedPrefsMobileToolbarRepository(SharedPreferences)` with `static const storageKey = 'teampilot.mobile_toolbar.v1'`; `InMemoryMobileToolbarRepository({MobileToolbarPrefs? initial})` exposing `int saveCount` and `MobileToolbarPrefs? lastSaved`.

- [ ] **Step 1: Write the failing test**

Create `client/test/repositories/mobile_toolbar_repository_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/models/toolbar_key.dart';
import 'package:teampilot/repositories/mobile_toolbar_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  group('sanitizeToolbarPrefs', () {
    test('defaults to the built-in order and count', () {
      final p = sanitizeToolbarPrefs();
      expect(p.groupOrder, defaultToolbarGroupIds);
      expect(p.visibleGroupCount, defaultVisibleToolbarGroupCount);
      expect(p.usage, isEmpty);
    });

    test('drops unknown ids, dedupes, appends missing groups at the tail', () {
      final p = sanitizeToolbarPrefs(
        groupOrder: ['signals', 'bogus', 'signals', 'arrows'],
      );
      expect(p.groupOrder.take(2), ['signals', 'arrows']);
      expect(p.groupOrder.length, defaultToolbarGroupIds.length);
      expect(p.groupOrder.toSet().length, p.groupOrder.length);
      expect(p.groupOrder, containsAll(defaultToolbarGroupIds));
    });

    test('clamps the visible count into 1..groups', () {
      expect(sanitizeToolbarPrefs(visibleGroupCount: 0).visibleGroupCount, 1);
      expect(sanitizeToolbarPrefs(visibleGroupCount: 99).visibleGroupCount, 16);
    });

    test('drops usage entries for unknown keys and non-positive counts', () {
      final p = sanitizeToolbarPrefs(
        usage: {'ctrl_c': 3, 'ghost': 9, 'esc': 0},
      );
      expect(p.usage, {'ctrl_c': 3});
    });
  });

  group('SharedPrefsMobileToolbarRepository', () {
    test('load on a fresh install returns sanitized defaults', () async {
      final repo = SharedPrefsMobileToolbarRepository(await prefsWith({}));
      final p = await repo.load();
      expect(p.groupOrder, defaultToolbarGroupIds);
      expect(p.visibleGroupCount, 4);
    });

    test('save then load round-trips', () async {
      final prefs = await prefsWith({});
      final repo = SharedPrefsMobileToolbarRepository(prefs);
      await repo.save(sanitizeToolbarPrefs(
        groupOrder: ['fkeys1', 'arrows'],
        visibleGroupCount: 6,
        usage: {'f1': 2},
      ));
      final loaded = await SharedPrefsMobileToolbarRepository(prefs).load();
      expect(loaded.groupOrder.take(2), ['fkeys1', 'arrows']);
      expect(loaded.visibleGroupCount, 6);
      expect(loaded.usage, {'f1': 2});
    });

    test('corrupt json falls back to defaults instead of throwing', () async {
      final repo = SharedPrefsMobileToolbarRepository(await prefsWith({
        SharedPrefsMobileToolbarRepository.storageKey: 'not json {',
      }));
      final p = await repo.load();
      expect(p.groupOrder, defaultToolbarGroupIds);
    });

    test('stored blob shape is the documented three keys', () async {
      final prefs = await prefsWith({});
      await SharedPrefsMobileToolbarRepository(prefs)
          .save(sanitizeToolbarPrefs(usage: {'esc': 1}));
      final raw =
          prefs.getString(SharedPrefsMobileToolbarRepository.storageKey)!;
      expect(
        (jsonDecode(raw) as Map).keys,
        containsAll(['groupOrder', 'visibleGroupCount', 'usage']),
      );
    });
  });

  test('InMemoryMobileToolbarRepository records saves', () async {
    final repo = InMemoryMobileToolbarRepository();
    expect((await repo.load()).groupOrder, defaultToolbarGroupIds);
    await repo.save(sanitizeToolbarPrefs(visibleGroupCount: 9));
    expect(repo.saveCount, 1);
    expect(repo.lastSaved!.visibleGroupCount, 9);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/repositories/mobile_toolbar_repository_test.dart`
Expected: FAIL — `Error: Method not found: 'sanitizeToolbarPrefs'`.

- [ ] **Step 3: Write the implementation**

Create `client/lib/repositories/mobile_toolbar_repository.dart`:

```dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/toolbar_key.dart';

/// Persisted layout of the mobile terminal toolbar.
@immutable
class MobileToolbarPrefs {
  const MobileToolbarPrefs({
    required this.groupOrder,
    required this.visibleGroupCount,
    required this.usage,
  });

  /// Every known group id, in display order.
  final List<String> groupOrder;

  /// How many leading groups the bar shows.
  final int visibleGroupCount;

  /// Tap counts per key id, used to surface the user's most-used keys.
  final Map<String, int> usage;

  MobileToolbarPrefs copyWith({
    List<String>? groupOrder,
    int? visibleGroupCount,
    Map<String, int>? usage,
  }) => MobileToolbarPrefs(
    groupOrder: groupOrder ?? this.groupOrder,
    visibleGroupCount: visibleGroupCount ?? this.visibleGroupCount,
    usage: usage ?? this.usage,
  );

  Map<String, Object?> toJson() => {
    'groupOrder': groupOrder,
    'visibleGroupCount': visibleGroupCount,
    'usage': usage,
  };
}

/// Normalizes anything read from disk (or from a UI mutation) into a usable
/// layout: unknown group ids are dropped, built-in groups that the stored order
/// has never seen are appended at the tail — so shipping a new group does not
/// invalidate an existing user's order — and the visible count is clamped.
MobileToolbarPrefs sanitizeToolbarPrefs({
  Iterable<String>? groupOrder,
  int? visibleGroupCount,
  Map<String, int>? usage,
}) {
  final known = defaultToolbarGroupIds;
  final ordered = <String>[];
  for (final id in groupOrder ?? const <String>[]) {
    if (known.contains(id) && !ordered.contains(id)) ordered.add(id);
  }
  for (final id in known) {
    if (!ordered.contains(id)) ordered.add(id);
  }
  final cleanUsage = <String, int>{};
  (usage ?? const <String, int>{}).forEach((key, count) {
    if (count > 0 && toolbarKeyById(key) != null) cleanUsage[key] = count;
  });
  return MobileToolbarPrefs(
    groupOrder: ordered,
    visibleGroupCount: (visibleGroupCount ?? defaultVisibleToolbarGroupCount)
        .clamp(1, ordered.length),
    usage: cleanUsage,
  );
}

abstract class MobileToolbarRepository {
  Future<MobileToolbarPrefs> load();
  Future<void> save(MobileToolbarPrefs prefs);
}

/// One versioned JSON blob, matching [PairingSettingsRepository]'s shape.
class SharedPrefsMobileToolbarRepository implements MobileToolbarRepository {
  const SharedPrefsMobileToolbarRepository(this._preferences);

  static const storageKey = 'teampilot.mobile_toolbar.v1';

  final SharedPreferences _preferences;

  @override
  Future<MobileToolbarPrefs> load() async {
    final map = _readMap();
    final order = map['groupOrder'];
    final usage = map['usage'];
    return sanitizeToolbarPrefs(
      groupOrder: order is List ? order.whereType<String>() : null,
      visibleGroupCount: map['visibleGroupCount'] is int
          ? map['visibleGroupCount'] as int
          : null,
      usage: usage is Map
          ? {
              for (final e in usage.entries)
                if (e.key is String && e.value is int)
                  e.key as String: e.value as int,
            }
          : null,
    );
  }

  @override
  Future<void> save(MobileToolbarPrefs prefs) =>
      _preferences.setString(storageKey, jsonEncode(prefs.toJson()));

  Map<String, Object?> _readMap() {
    final stored = _preferences.getString(storageKey);
    if (stored == null || stored.isEmpty) return const <String, Object?>{};
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) return const <String, Object?>{};
      return Map<String, Object?>.from(decoded);
    } on FormatException {
      return const <String, Object?>{};
    }
  }
}

class InMemoryMobileToolbarRepository implements MobileToolbarRepository {
  InMemoryMobileToolbarRepository({MobileToolbarPrefs? initial})
    : _prefs = initial ?? sanitizeToolbarPrefs();

  MobileToolbarPrefs _prefs;

  /// Number of [save] calls — lets tests assert the usage debounce coalesces.
  int saveCount = 0;

  MobileToolbarPrefs? lastSaved;

  @override
  Future<MobileToolbarPrefs> load() async => _prefs;

  @override
  Future<void> save(MobileToolbarPrefs prefs) async {
    _prefs = prefs;
    lastSaved = prefs;
    saveCount++;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/repositories/mobile_toolbar_repository_test.dart`
Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/yitouxiaomaolv/git/cmux
git add client/lib/repositories/mobile_toolbar_repository.dart client/test/repositories/mobile_toolbar_repository_test.dart
git commit -m "feat(mobile): persist terminal toolbar layout and key usage"
```

---

### Task 4: `MobileToolbarCubit`

**Files:**
- Create: `client/lib/cubits/mobile_toolbar_cubit.dart`
- Test: `client/test/cubits/mobile_toolbar_cubit_test.dart`

**Interfaces:**
- Consumes: `ToolbarKey`, `toolbarKeyById`, `toolbarGroupById`, `defaultToolbarGroupIds` (Task 1); `encodeToolbarKey`, `terminalizeNewlines` (Task 2); `MobileToolbarRepository`, `MobileToolbarPrefs`, `sanitizeToolbarPrefs` (Task 3).
- Produces: `class MobileToolbarState { List<String> groupOrder; int visibleGroupCount; Map<String,int> usage; bool ctrl; bool alt; List<ToolbarKeyGroup> get visibleGroups; List<ToolbarKey> get mostUsedKeys; }` and `class MobileToolbarCubit extends Cubit<MobileToolbarState>` with `MobileToolbarCubit({required MobileToolbarRepository repository, required void Function(List<int>) sendInput, Future<String?> Function()? readClipboard, Duration usageFlushDelay = const Duration(seconds: 1)})`, methods `Future<void> load()`, `Future<void> tapKey(ToolbarKey key)`, `void toggleCtrl()`, `void toggleAlt()`, `Future<void> setVisibleGroupCount(int count)`, `Future<void> reorderGroups(int oldIndex, int newIndex)`, `Future<void> resetLayout()`.

- [ ] **Step 1: Write the failing test**

Create `client/test/cubits/mobile_toolbar_cubit_test.dart`:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/mobile_toolbar_cubit.dart';
import 'package:teampilot/models/toolbar_key.dart';
import 'package:teampilot/repositories/mobile_toolbar_repository.dart';

void main() {
  late List<List<int>> sent;
  late InMemoryMobileToolbarRepository repo;

  MobileToolbarCubit build({String? clipboard}) => MobileToolbarCubit(
    repository: repo,
    sendInput: sent.add,
    readClipboard: () async => clipboard,
  );

  ToolbarKey key(String id) => toolbarKeyById(id)!;

  setUp(() {
    sent = [];
    repo = InMemoryMobileToolbarRepository();
  });

  test('load hydrates order and visible count from the repository', () async {
    repo = InMemoryMobileToolbarRepository(
      initial: sanitizeToolbarPrefs(
        groupOrder: ['signals'],
        visibleGroupCount: 2,
      ),
    );
    final cubit = build();
    await cubit.load();
    expect(cubit.state.groupOrder.first, 'signals');
    expect(cubit.state.visibleGroupCount, 2);
    expect(cubit.state.visibleGroups.map((g) => g.id).length, 2);
    await cubit.close();
  });

  test('a plain key sends its bytes and counts usage', () async {
    final cubit = build();
    await cubit.tapKey(key('ctrl_c'));
    expect(sent, [[0x03]]);
    expect(cubit.state.usage['ctrl_c'], 1);
    await cubit.close();
  });

  test('Ctrl and Alt are mutually exclusive and one-shot', () async {
    final cubit = build();
    await cubit.tapKey(key('ctrl'));
    expect(cubit.state.ctrl, isTrue);
    await cubit.tapKey(key('alt'));
    expect(cubit.state.ctrl, isFalse);
    expect(cubit.state.alt, isTrue);
    await cubit.tapKey(key('slash')); // Alt+/
    expect(sent, [[0x1b, 0x2f]]);
    expect(cubit.state.alt, isFalse, reason: 'modifier must reset after use');
    await cubit.tapKey(key('slash'));
    expect(sent.last, [0x2f]);
    await cubit.close();
  });

  test('Ctrl rewrites an arrow into the xterm modifier form', () async {
    final cubit = build();
    await cubit.tapKey(key('ctrl'));
    await cubit.tapKey(key('arrow_up'));
    expect(sent, [[0x1b, 0x5b, 0x31, 0x3b, 0x35, 0x41]]);
    await cubit.close();
  });

  test('modifier keys are not counted as usage', () async {
    final cubit = build();
    await cubit.tapKey(key('ctrl'));
    await cubit.tapKey(key('alt'));
    expect(cubit.state.usage, isEmpty);
    await cubit.close();
  });

  test('paste normalizes newlines to CR, bypasses modifiers and usage', () async {
    final cubit = build(clipboard: 'echo a\nls\r\n');
    await cubit.tapKey(key('ctrl'));
    await cubit.tapKey(key('paste'));
    expect(String.fromCharCodes(sent.single), 'echo a\rls\r');
    expect(cubit.state.usage, isEmpty);
    expect(cubit.state.ctrl, isTrue, reason: 'paste must not consume Ctrl');
    await cubit.close();
  });

  test('empty or missing clipboard sends nothing', () async {
    final cubit = build(clipboard: null);
    await cubit.tapKey(key('paste'));
    final empty = build(clipboard: '');
    await empty.tapKey(key('paste'));
    expect(sent, isEmpty);
    await cubit.close();
    await empty.close();
  });

  test('reorder and visible count persist immediately', () async {
    final cubit = build();
    await cubit.load();
    await cubit.reorderGroups(3, 0); // signals to the front
    expect(cubit.state.groupOrder.first, 'signals');
    expect(repo.lastSaved!.groupOrder.first, 'signals');
    await cubit.setVisibleGroupCount(7);
    expect(repo.lastSaved!.visibleGroupCount, 7);
    await cubit.setVisibleGroupCount(999);
    expect(cubit.state.visibleGroupCount, 16, reason: 'clamped');
    await cubit.close();
  });

  test('resetLayout restores built-in order and count, keeps usage', () async {
    final cubit = build();
    await cubit.load();
    await cubit.tapKey(key('esc'));
    await cubit.reorderGroups(5, 0);
    await cubit.resetLayout();
    expect(cubit.state.groupOrder, defaultToolbarGroupIds);
    expect(cubit.state.visibleGroupCount, defaultVisibleToolbarGroupCount);
    expect(cubit.state.usage['esc'], 1);
    await cubit.close();
  });

  test('mostUsedKeys ranks by tap count, highest first', () async {
    final cubit = build();
    await cubit.tapKey(key('esc'));
    await cubit.tapKey(key('tab'));
    await cubit.tapKey(key('tab'));
    expect(cubit.state.mostUsedKeys.map((k) => k.id).take(2), ['tab', 'esc']);
    await cubit.close();
  });

  test('usage writes are debounced into a single save', () {
    fakeAsync((async) {
      final cubit = build();
      cubit.tapKey(key('esc'));
      cubit.tapKey(key('esc'));
      cubit.tapKey(key('tab'));
      async.flushMicrotasks();
      expect(repo.saveCount, 0, reason: 'not written yet');
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(repo.saveCount, 1);
      expect(repo.lastSaved!.usage, {'esc': 2, 'tab': 1});
      cubit.close();
      async.flushMicrotasks();
    });
  });

  test('close flushes a pending usage write', () async {
    final cubit = build();
    await cubit.tapKey(key('esc'));
    expect(repo.saveCount, 0);
    await cubit.close();
    expect(repo.saveCount, 1);
    expect(repo.lastSaved!.usage, {'esc': 1});
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/mobile_toolbar_cubit_test.dart`
Expected: FAIL — `Error: Couldn't find constructor 'MobileToolbarCubit'`.

- [ ] **Step 3: Write the implementation**

Create `client/lib/cubits/mobile_toolbar_cubit.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/toolbar_key.dart';
import '../repositories/mobile_toolbar_repository.dart';
import '../services/terminal/toolbar_key_encoder.dart';

@immutable
class MobileToolbarState {
  const MobileToolbarState({
    required this.groupOrder,
    required this.visibleGroupCount,
    required this.usage,
    this.ctrl = false,
    this.alt = false,
  });

  MobileToolbarState.fromPrefs(MobileToolbarPrefs prefs)
    : groupOrder = prefs.groupOrder,
      visibleGroupCount = prefs.visibleGroupCount,
      usage = prefs.usage,
      ctrl = false,
      alt = false;

  final List<String> groupOrder;
  final int visibleGroupCount;
  final Map<String, int> usage;

  /// One-shot modifiers: set by tapping Ctrl / Alt, cleared by the next key.
  final bool ctrl;
  final bool alt;

  List<ToolbarKeyGroup> get visibleGroups => groupOrder
      .take(visibleGroupCount)
      .map(toolbarGroupById)
      .whereType<ToolbarKeyGroup>()
      .toList(growable: false);

  /// Keys the user actually presses, most-used first — shown on the customize
  /// page so reordering is an informed choice rather than a guess.
  List<ToolbarKey> get mostUsedKeys {
    final entries = usage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries
        .map((e) => toolbarKeyById(e.key))
        .whereType<ToolbarKey>()
        .toList(growable: false);
  }

  MobileToolbarPrefs get prefs => MobileToolbarPrefs(
    groupOrder: groupOrder,
    visibleGroupCount: visibleGroupCount,
    usage: usage,
  );

  MobileToolbarState copyWith({
    List<String>? groupOrder,
    int? visibleGroupCount,
    Map<String, int>? usage,
    bool? ctrl,
    bool? alt,
  }) => MobileToolbarState(
    groupOrder: groupOrder ?? this.groupOrder,
    visibleGroupCount: visibleGroupCount ?? this.visibleGroupCount,
    usage: usage ?? this.usage,
    ctrl: ctrl ?? this.ctrl,
    alt: alt ?? this.alt,
  );
}

/// Owns the mobile toolbar's modifier state and persisted layout.
///
/// Deliberately ignorant of pairing: [sendInput] is injected, so the same cubit
/// works for the pairing mirror today and any other terminal host later.
class MobileToolbarCubit extends Cubit<MobileToolbarState> {
  MobileToolbarCubit({
    required MobileToolbarRepository repository,
    required void Function(List<int> bytes) sendInput,
    Future<String?> Function()? readClipboard,
    this.usageFlushDelay = const Duration(seconds: 1),
  }) : _repository = repository,
       _sendInput = sendInput,
       _readClipboard = readClipboard ?? _systemClipboard,
       super(MobileToolbarState.fromPrefs(sanitizeToolbarPrefs()));

  static Future<String?> _systemClipboard() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  final MobileToolbarRepository _repository;
  final void Function(List<int> bytes) _sendInput;
  final Future<String?> Function() _readClipboard;

  /// Tap counters change on every key press; coalesce them so a burst of arrow
  /// repeats is one disk write, not eighty.
  final Duration usageFlushDelay;
  Timer? _usageFlush;

  Future<void> load() async {
    emit(MobileToolbarState.fromPrefs(await _repository.load()));
  }

  void toggleCtrl() => emit(state.copyWith(ctrl: !state.ctrl, alt: false));

  void toggleAlt() => emit(state.copyWith(alt: !state.alt, ctrl: false));

  Future<void> tapKey(ToolbarKey key) async {
    switch (key.special) {
      case ToolbarKeySpecial.ctrl:
        toggleCtrl();
        return;
      case ToolbarKeySpecial.alt:
        toggleAlt();
        return;
      case ToolbarKeySpecial.paste:
        await _paste();
        return;
      case null:
        break;
    }
    final bytes = encodeToolbarKey(key.bytes, ctrl: state.ctrl, alt: state.alt);
    if (bytes.isEmpty) return;
    _sendInput(bytes);
    _bumpUsage(key.id);
    if (state.ctrl || state.alt) {
      emit(state.copyWith(ctrl: false, alt: false));
    }
  }

  /// Paste is raw text, so modifiers do not apply and it earns no usage count
  /// (Nexterm parity). Newlines become CR or the shell never runs the line.
  Future<void> _paste() async {
    final text = await _readClipboard();
    if (text == null || text.isEmpty) return;
    _sendInput(utf8.encode(terminalizeNewlines(text)));
  }

  Future<void> setVisibleGroupCount(int count) => _persist(
    sanitizeToolbarPrefs(
      groupOrder: state.groupOrder,
      visibleGroupCount: count,
      usage: state.usage,
    ),
  );

  Future<void> reorderGroups(int oldIndex, int newIndex) {
    final order = [...state.groupOrder];
    final moved = order.removeAt(oldIndex);
    order.insert(newIndex.clamp(0, order.length), moved);
    return _persist(
      sanitizeToolbarPrefs(
        groupOrder: order,
        visibleGroupCount: state.visibleGroupCount,
        usage: state.usage,
      ),
    );
  }

  /// Restores the built-in order and count. Usage history survives — it is the
  /// user's data, not layout.
  Future<void> resetLayout() => _persist(
    sanitizeToolbarPrefs(
      groupOrder: defaultToolbarGroupIds,
      visibleGroupCount: defaultVisibleToolbarGroupCount,
      usage: state.usage,
    ),
  );

  Future<void> _persist(MobileToolbarPrefs prefs) async {
    emit(state.copyWith(
      groupOrder: prefs.groupOrder,
      visibleGroupCount: prefs.visibleGroupCount,
      usage: prefs.usage,
    ));
    _usageFlush?.cancel();
    _usageFlush = null;
    await _repository.save(prefs);
  }

  void _bumpUsage(String keyId) {
    final usage = {...state.usage};
    usage[keyId] = (usage[keyId] ?? 0) + 1;
    emit(state.copyWith(usage: usage));
    _usageFlush?.cancel();
    _usageFlush = Timer(usageFlushDelay, _flushUsage);
  }

  void _flushUsage() {
    _usageFlush = null;
    _repository.save(state.prefs);
  }

  @override
  Future<void> close() async {
    if (_usageFlush != null) {
      _usageFlush!.cancel();
      _usageFlush = null;
      await _repository.save(state.prefs);
    }
    return super.close();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/cubits/mobile_toolbar_cubit_test.dart`
Expected: PASS, 12 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/yitouxiaomaolv/git/cmux
git add client/lib/cubits/mobile_toolbar_cubit.dart client/test/cubits/mobile_toolbar_cubit_test.dart
git commit -m "feat(mobile): add toolbar cubit with one-shot modifiers and usage tracking"
```

---

### Task 5: The 44px toolbar, wired into the mirror page

**Files:**
- Create: `client/lib/pages/pairing/mobile_toolbar/mobile_keyboard_toolbar.dart`
- Modify: `client/lib/utils/ui/app_keys.dart` (replace `pairingMirrorCtrlCButton` at `:72`)
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb` (add `mobileToolbarHideKeyboard`; delete `pairingMirrorInputHint` and `pairingSendCtrlC`)
- Modify: `client/lib/pages/pairing/pairing_mirror_page.dart` (`:1-13` imports, `:28-59` state, `:111-115` bottom slot, delete `_MirrorBar` `:124-181`)
- Test: `client/test/pages/pairing/mobile_keyboard_toolbar_test.dart`

**Interfaces:**
- Consumes: `MobileToolbarCubit`, `MobileToolbarState` (Task 4); `ToolbarKey`, `ToolbarKeyGroup` (Task 1); `InMemoryMobileToolbarRepository` (Task 3, tests only).
- Produces: `class MobileKeyboardToolbar extends StatelessWidget` with `static const double barHeight = 44`; `AppKeys.mobileToolbarKey(String id)`, `AppKeys.mobileToolbar`, `AppKeys.mobileToolbarHideKeyboardButton`.

**Deviation from the spec, deliberate:** the spec said to keep `AppKeys.pairingMirrorCtrlCButton` on the `^C` cap. A widget takes one key, and every other cap needs `mobileToolbarKey(id)`, so `^C` uses `mobileToolbarKey('ctrl_c')` like its neighbours and the old constant is deleted. Verified no test or source references it outside `app_keys.dart`.

- [ ] **Step 1: Add the l10n string and widget keys**

In `client/lib/l10n/app_en.arb`, delete the `pairingSendCtrlC` and `pairingMirrorInputHint` entries and add (keep the file's trailing `}` intact — the last entry has no comma):

```json
  "mobileToolbarHideKeyboard": "Hide keyboard"
```

In `client/lib/l10n/app_zh.arb`, delete the same two entries and add:

```json
  "mobileToolbarHideKeyboard": "收起键盘"
```

In `client/lib/utils/ui/app_keys.dart`, replace the line

```dart
  static const pairingMirrorCtrlCButton = Key('pairing-mirror-ctrl-c');
```

with

```dart
  static const mobileToolbar = Key('mobile-toolbar');
  static const mobileToolbarHideKeyboardButton = Key('mobile-toolbar-hide-kb');
  static Key mobileToolbarKey(String keyId) => Key('mobile-toolbar-key-$keyId');
```

Then run: `cd client && dart run tool/gen_warmup_glyphs.dart`

- [ ] **Step 2: Write the failing test**

Create `client/test/pages/pairing/mobile_keyboard_toolbar_test.dart`:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/mobile_toolbar_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/toolbar_key.dart';
import 'package:teampilot/pages/pairing/mobile_toolbar/mobile_keyboard_toolbar.dart';
import 'package:teampilot/repositories/mobile_toolbar_repository.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

void main() {
  late List<List<int>> sent;
  late MobileToolbarCubit cubit;

  setUp(() {
    sent = [];
    cubit = MobileToolbarCubit(
      repository: InMemoryMobileToolbarRepository(),
      sendInput: sent.add,
      readClipboard: () async => null,
    );
  });

  tearDown(() => cubit.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox.expand()),
              BlocProvider.value(
                value: cubit,
                child: const MobileKeyboardToolbar(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders the default four groups and nothing beyond', (t) async {
    await pump(t);
    expect(find.byKey(AppKeys.mobileToolbar), findsOneWidget);
    for (final id in ['arrow_left', 'paste', 'esc', 'ctrl_c', 'ctrl_s']) {
      expect(find.byKey(AppKeys.mobileToolbarKey(id)), findsOneWidget,
          reason: '$id is in the first four groups');
    }
    expect(find.byKey(AppKeys.mobileToolbarKey('f1')), findsNothing);
    expect(find.byKey(AppKeys.mobileToolbarKey('home')), findsNothing);
  });

  testWidgets('tapping ^C sends 0x03', (t) async {
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileToolbarKey('ctrl_c')));
    await t.pump();
    expect(sent, [[0x03]]);
  });

  testWidgets('Ctrl then a key sends the control code once', (t) async {
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileToolbarKey('ctrl')));
    await t.pump();
    await t.tap(find.byKey(AppKeys.mobileToolbarKey('esc')));
    await t.pump();
    expect(sent, [[0x1b]], reason: 'Esc is already a control code');
    expect(cubit.state.ctrl, isFalse);
  });

  testWidgets('holding an arrow auto-repeats', (t) async {
    await pump(t);
    final gesture = await t.startGesture(
      t.getCenter(find.byKey(AppKeys.mobileToolbarKey('arrow_up'))),
    );
    await t.pump(kLongPressTimeout + const Duration(milliseconds: 10));
    await t.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await t.pump();
    expect(sent.length, greaterThanOrEqualTo(2));
    expect(sent.first, [0x1b, 0x5b, 0x41]);
  });

  testWidgets('keys still send after the keyboard is hidden', (t) async {
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileToolbarHideKeyboardButton));
    await t.pump();
    await t.tap(find.byKey(AppKeys.mobileToolbarKey('tab')));
    await t.pump();
    expect(sent, [[0x09]]);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd client && flutter test test/pages/pairing/mobile_keyboard_toolbar_test.dart`
Expected: FAIL — `Error: Couldn't resolve … mobile_keyboard_toolbar.dart`.

- [ ] **Step 4: Write the toolbar widget**

Create `client/lib/pages/pairing/mobile_toolbar/mobile_keyboard_toolbar.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/mobile_toolbar_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/toolbar_key.dart';
import '../../../utils/ui/app_keys.dart';

/// Shortcut-key strip that sits between the mirrored terminal and the soft
/// keyboard, giving a phone the keys iOS/Android simply do not have: Esc, Tab,
/// arrows, signals, F-keys.
///
/// Keys write through [MobileToolbarCubit], never through the terminal's focus
/// node, so the bar keeps working after the soft keyboard is dismissed.
class MobileKeyboardToolbar extends StatelessWidget {
  const MobileKeyboardToolbar({super.key});

  static const double barHeight = 44;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: AppKeys.mobileToolbar,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: barHeight,
          child: Row(
            children: [
              Expanded(
                child: BlocBuilder<MobileToolbarCubit, MobileToolbarState>(
                  builder: (context, state) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(children: _caps(context, state)),
                  ),
                ),
              ),
              TpIconButton(
                key: AppKeys.mobileToolbarHideKeyboardButton,
                icon: Icons.keyboard_hide,
                tooltip: context.l10n.mobileToolbarHideKeyboard,
                size: barHeight,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _caps(BuildContext context, MobileToolbarState state) {
    final cubit = context.read<MobileToolbarCubit>();
    final caps = <Widget>[];
    for (final group in state.visibleGroups) {
      if (caps.isNotEmpty) caps.add(const _GroupDivider());
      for (final key in group.keys) {
        caps.add(
          _ToolbarKeyCap(
            key: AppKeys.mobileToolbarKey(key.id),
            toolbarKey: key,
            active: switch (key.special) {
              ToolbarKeySpecial.ctrl => state.ctrl,
              ToolbarKeySpecial.alt => state.alt,
              _ => false,
            },
            onPress: () {
              HapticFeedback.lightImpact();
              cubit.tapKey(key);
            },
          ),
        );
      }
    }
    return caps;
  }
}

class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 24,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

/// One key cap. Owns the auto-repeat timer for held arrow keys — a TUI is
/// unusable if moving five lines up needs five taps.
class _ToolbarKeyCap extends StatefulWidget {
  const _ToolbarKeyCap({
    super.key,
    required this.toolbarKey,
    required this.active,
    required this.onPress,
  });

  final ToolbarKey toolbarKey;
  final bool active;
  final VoidCallback onPress;

  @override
  State<_ToolbarKeyCap> createState() => _ToolbarKeyCapState();
}

class _ToolbarKeyCapState extends State<_ToolbarKeyCap> {
  static const _repeatInterval = Duration(milliseconds: 80);

  Timer? _repeat;

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  void _startRepeat() {
    widget.onPress();
    _repeat = Timer.periodic(_repeatInterval, (_) => widget.onPress());
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final repeatable = widget.toolbarKey.repeatable;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onPress,
      onLongPressStart: repeatable ? (_) => _startRepeat() : null,
      onLongPressEnd: repeatable ? (_) => _stopRepeat() : null,
      onLongPressCancel: repeatable ? _stopRepeat : null,
      child: Container(
        constraints: const BoxConstraints(minWidth: 40),
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.active ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          widget.toolbarKey.label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1,
            color: widget.active ? cs.onPrimary : cs.onSurface,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd client && flutter test test/pages/pairing/mobile_keyboard_toolbar_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 6: Wire the toolbar into the mirror page**

In `client/lib/pages/pairing/pairing_mirror_page.dart`:

Add to the imports:

```dart
import 'package:shared_preferences/shared_preferences.dart';

import '../../cubits/mobile_toolbar_cubit.dart';
import '../../repositories/mobile_toolbar_repository.dart';
import 'mobile_toolbar/mobile_keyboard_toolbar.dart';
```

Add the field next to `_engine` / `_controller`:

```dart
  late final MobileToolbarCubit _toolbar;
```

At the end of `initState`, after `_localInput = _engine.output.listen(cubit.sendInput);`:

```dart
    // Toolbar keys bypass the engine and go straight out as input frames, so
    // they work whether or not the terminal holds focus.
    _toolbar = MobileToolbarCubit(
      repository: SharedPrefsMobileToolbarRepository(
        context.read<SharedPreferences>(),
      ),
      sendInput: cubit.sendInput,
    );
    _toolbar.load();
```

In `dispose`, before `super.dispose()`:

```dart
    _toolbar.close();
```

Replace the `_MirrorBar(...)` child (`:111-115`) with:

```dart
              BlocProvider.value(
                value: _toolbar,
                child: const MobileKeyboardToolbar(),
              ),
```

Delete the whole `_MirrorBar` class (`:124-181`) and the now-unused `final l10n = context.l10n;` line in `build` plus the `l10n_extensions.dart` import if the analyzer flags them as unused.

- [ ] **Step 7: Verify the whole suite and analyzer**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1 | tail -3`
Expected: no `error •` lines mentioning `pairing_mirror_page.dart`, `mobile_keyboard_toolbar.dart`, `app_keys.dart`.

Run: `cd client && flutter test --exclude-tags integration 2>&1 | tail -5`
Expected: only the two known pre-existing failures listed in Global Constraints.

- [ ] **Step 8: Commit**

```bash
cd /Users/yitouxiaomaolv/git/cmux
git add client/lib/pages/pairing/mobile_toolbar/mobile_keyboard_toolbar.dart \
        client/lib/pages/pairing/pairing_mirror_page.dart \
        client/lib/utils/ui/app_keys.dart \
        client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
        client/lib/widgets/warmup_glyphs.g.dart \
        client/test/pages/pairing/mobile_keyboard_toolbar_test.dart
git commit -m "feat(mobile): show a shortcut-key toolbar on the pairing mirror"
```

---

### Task 6: Customize page (reorder, visible count, most-used, reset)

**Files:**
- Create: `client/lib/pages/pairing/mobile_toolbar/mobile_toolbar_labels.dart`
- Create: `client/lib/pages/pairing/mobile_toolbar/mobile_toolbar_customize_page.dart`
- Modify: `client/lib/pages/pairing/mobile_toolbar/mobile_keyboard_toolbar.dart` (add the gear button left of hide-keyboard)
- Modify: `client/lib/utils/ui/app_keys.dart`, `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/pairing/mobile_toolbar_customize_page_test.dart`

**Interfaces:**
- Consumes: `MobileToolbarCubit` (`reorderGroups`, `setVisibleGroupCount`, `resetLayout`, `state.mostUsedKeys`) from Task 4; `defaultToolbarGroupIds`, `toolbarGroupById` from Task 1.
- Produces: `String toolbarGroupLabel(String groupId, AppLocalizations l10n)`; `class MobileToolbarCustomizePage extends StatelessWidget` with `static Route<void> route(MobileToolbarCubit cubit)`; `AppKeys.mobileToolbarCustomizeButton`, `AppKeys.mobileToolbarCustomizePage`, `AppKeys.mobileToolbarGroupTile(String)`, `AppKeys.mobileToolbarResetButton`.

**Deviation from the spec, deliberate:** the spec put the entry in `mobile_settings_sheet.dart`. That sheet hangs off the paired-hosts page, where no `MobileToolbarCubit` exists (it is created by `PairingMirrorPage`), so the entry is a gear button in the toolbar itself instead — matching Nexterm, which also keeps its toolbar-customize entry next to the toolbar. `mobile_settings_sheet.dart` is not touched.

- [ ] **Step 1: Add l10n strings and widget keys**

Append to `client/lib/l10n/app_en.arb` (before the closing `}`, comma after the previous last entry):

```json
  "mobileToolbarCustomize": "Customize keys",
  "mobileToolbarVisibleGroups": "Visible groups: {count}",
  "@mobileToolbarVisibleGroups": {
    "placeholders": { "count": { "type": "int" } }
  },
  "mobileToolbarMostUsed": "Most used",
  "mobileToolbarReorderHint": "Drag to reorder. The first groups appear first on the bar.",
  "mobileToolbarReset": "Reset to default",
  "mobileToolbarGroupArrows": "Arrows",
  "mobileToolbarGroupClipboard": "Clipboard",
  "mobileToolbarGroupTerminalCtrl": "Terminal control",
  "mobileToolbarGroupSignals": "Signals",
  "mobileToolbarGroupSymbols1": "Symbols 1",
  "mobileToolbarGroupNavigation": "Navigation",
  "mobileToolbarGroupEditing": "Editing",
  "mobileToolbarGroupSearch": "Search",
  "mobileToolbarGroupPunctuation": "Punctuation",
  "mobileToolbarGroupSymbols2": "Symbols 2",
  "mobileToolbarGroupBrackets1": "Brackets 1",
  "mobileToolbarGroupBrackets2": "Brackets 2",
  "mobileToolbarGroupFkeys1": "F1–F4",
  "mobileToolbarGroupFkeys2": "F5–F8",
  "mobileToolbarGroupFkeys3": "F9–F12",
  "mobileToolbarGroupAdvanced": "Advanced control"
```

Append the same keys to `client/lib/l10n/app_zh.arb` with these values (the `@mobileToolbarVisibleGroups` metadata block belongs only in the English template):

```json
  "mobileToolbarCustomize": "自定义按键",
  "mobileToolbarVisibleGroups": "显示组数：{count}",
  "mobileToolbarMostUsed": "高频按键",
  "mobileToolbarReorderHint": "拖动排序，靠前的组显示在工具栏左侧。",
  "mobileToolbarReset": "恢复默认",
  "mobileToolbarGroupArrows": "方向键",
  "mobileToolbarGroupClipboard": "剪贴板",
  "mobileToolbarGroupTerminalCtrl": "终端控制",
  "mobileToolbarGroupSignals": "信号",
  "mobileToolbarGroupSymbols1": "符号 1",
  "mobileToolbarGroupNavigation": "导航",
  "mobileToolbarGroupEditing": "编辑",
  "mobileToolbarGroupSearch": "搜索",
  "mobileToolbarGroupPunctuation": "标点",
  "mobileToolbarGroupSymbols2": "符号 2",
  "mobileToolbarGroupBrackets1": "括号 1",
  "mobileToolbarGroupBrackets2": "括号 2",
  "mobileToolbarGroupFkeys1": "F1–F4",
  "mobileToolbarGroupFkeys2": "F5–F8",
  "mobileToolbarGroupFkeys3": "F9–F12",
  "mobileToolbarGroupAdvanced": "高级控制"
```

Add to `client/lib/utils/ui/app_keys.dart` beside the other toolbar keys:

```dart
  static const mobileToolbarCustomizeButton = Key('mobile-toolbar-customize');
  static const mobileToolbarCustomizePage = Key('mobile-toolbar-customize-page');
  static const mobileToolbarResetButton = Key('mobile-toolbar-reset');
  static Key mobileToolbarGroupTile(String groupId) =>
      Key('mobile-toolbar-group-$groupId');
```

Run: `cd client && dart run tool/gen_warmup_glyphs.dart`

- [ ] **Step 2: Write the failing test**

Create `client/test/pages/pairing/mobile_toolbar_customize_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/mobile_toolbar_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/toolbar_key.dart';
import 'package:teampilot/pages/pairing/mobile_toolbar/mobile_toolbar_customize_page.dart';
import 'package:teampilot/repositories/mobile_toolbar_repository.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

void main() {
  late InMemoryMobileToolbarRepository repo;
  late MobileToolbarCubit cubit;

  setUp(() async {
    repo = InMemoryMobileToolbarRepository();
    cubit = MobileToolbarCubit(
      repository: repo,
      sendInput: (_) {},
      readClipboard: () async => null,
    );
    await cubit.load();
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
          child: const MobileToolbarCustomizePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists every group with its localized name', (t) async {
    await pump(t);
    expect(find.byKey(AppKeys.mobileToolbarCustomizePage), findsOneWidget);
    expect(find.text('Arrows'), findsOneWidget);
    expect(find.text('Visible groups: 4'), findsOneWidget);
    for (final id in defaultToolbarGroupIds) {
      expect(find.byKey(AppKeys.mobileToolbarGroupTile(id)), findsOneWidget);
    }
  });

  testWidgets('increasing the visible count persists', (t) async {
    await pump(t);
    await t.tap(find.byIcon(Icons.add));
    await t.pumpAndSettle();
    expect(cubit.state.visibleGroupCount, 5);
    expect(repo.lastSaved!.visibleGroupCount, 5);
    expect(find.text('Visible groups: 5'), findsOneWidget);
  });

  testWidgets('reset restores the built-in order', (t) async {
    await cubit.reorderGroups(4, 0);
    expect(cubit.state.groupOrder.first, isNot('arrows'));
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileToolbarResetButton));
    await t.pumpAndSettle();
    expect(cubit.state.groupOrder, defaultToolbarGroupIds);
    expect(repo.lastSaved!.groupOrder, defaultToolbarGroupIds);
  });

  testWidgets('most-used section appears once a key has been pressed', (t) async {
    await pump(t);
    expect(find.text('Most used'), findsNothing);
    await cubit.tapKey(toolbarKeyById('esc')!);
    await t.pumpAndSettle();
    expect(find.text('Most used'), findsOneWidget);
    expect(find.text('Esc'), findsWidgets);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd client && flutter test test/pages/pairing/mobile_toolbar_customize_page_test.dart`
Expected: FAIL — `Error: Couldn't resolve … mobile_toolbar_customize_page.dart`.

- [ ] **Step 4: Write the group-label lookup**

Create `client/lib/pages/pairing/mobile_toolbar/mobile_toolbar_labels.dart`:

```dart
import '../../../l10n/app_localizations.dart';

/// Localized display name for a toolbar group.
///
/// Group ids are stable storage keys; names are UI. Keeping the mapping here
/// means `toolbar_key.dart` stays a pure data file with no l10n dependency.
String toolbarGroupLabel(String groupId, AppLocalizations l10n) =>
    switch (groupId) {
      'arrows' => l10n.mobileToolbarGroupArrows,
      'clipboard' => l10n.mobileToolbarGroupClipboard,
      'terminal_ctrl' => l10n.mobileToolbarGroupTerminalCtrl,
      'signals' => l10n.mobileToolbarGroupSignals,
      'symbols1' => l10n.mobileToolbarGroupSymbols1,
      'navigation' => l10n.mobileToolbarGroupNavigation,
      'editing' => l10n.mobileToolbarGroupEditing,
      'search' => l10n.mobileToolbarGroupSearch,
      'punctuation' => l10n.mobileToolbarGroupPunctuation,
      'symbols2' => l10n.mobileToolbarGroupSymbols2,
      'brackets1' => l10n.mobileToolbarGroupBrackets1,
      'brackets2' => l10n.mobileToolbarGroupBrackets2,
      'fkeys1' => l10n.mobileToolbarGroupFkeys1,
      'fkeys2' => l10n.mobileToolbarGroupFkeys2,
      'fkeys3' => l10n.mobileToolbarGroupFkeys3,
      'advanced' => l10n.mobileToolbarGroupAdvanced,
      _ => groupId,
    };
```

- [ ] **Step 5: Write the customize page**

Create `client/lib/pages/pairing/mobile_toolbar/mobile_toolbar_customize_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/mobile_toolbar_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/toolbar_key.dart';
import '../../../utils/ui/app_keys.dart';
import 'mobile_toolbar_labels.dart';

/// Lets the user decide which key groups the toolbar shows and in what order.
///
/// The bar only has room for a handful of groups on a phone, so ordering is the
/// whole feature: drag the groups you use to the top, raise the visible count
/// until the bar is as busy as you like.
class MobileToolbarCustomizePage extends StatelessWidget {
  const MobileToolbarCustomizePage({super.key});

  /// Route helper so callers do not have to remember to re-provide the cubit.
  static Route<void> route(MobileToolbarCubit cubit) => MaterialPageRoute(
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: const MobileToolbarCustomizePage(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final spacing = context.tpSpacing;
    final cubit = context.read<MobileToolbarCubit>();
    return Scaffold(
      key: AppKeys.mobileToolbarCustomizePage,
      appBar: AppBar(
        title: Text(l10n.mobileToolbarCustomize),
        actions: [
          TpIconButton(
            key: AppKeys.mobileToolbarResetButton,
            icon: Icons.restart_alt,
            tooltip: l10n.mobileToolbarReset,
            onTap: cubit.resetLayout,
          ),
          SizedBox(width: spacing.sm),
        ],
      ),
      body: BlocBuilder<MobileToolbarCubit, MobileToolbarState>(
        builder: (context, state) => Column(
          children: [
            Padding(
              padding: EdgeInsets.all(spacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.mobileToolbarVisibleGroups(state.visibleGroupCount),
                      style: styles.mdMedium,
                    ),
                  ),
                  TpIconButton(
                    icon: Icons.remove,
                    tooltip: l10n.mobileToolbarVisibleGroups(
                      state.visibleGroupCount - 1,
                    ),
                    onTap: () => cubit.setVisibleGroupCount(
                      state.visibleGroupCount - 1,
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  TpIconButton(
                    icon: Icons.add,
                    tooltip: l10n.mobileToolbarVisibleGroups(
                      state.visibleGroupCount + 1,
                    ),
                    onTap: () => cubit.setVisibleGroupCount(
                      state.visibleGroupCount + 1,
                    ),
                  ),
                ],
              ),
            ),
            if (state.mostUsedKeys.isNotEmpty)
              _MostUsed(keys: state.mostUsedKeys.take(8).toList()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.lg),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.mobileToolbarReorderHint,
                  style: styles.sm,
                ),
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: EdgeInsets.symmetric(vertical: spacing.md),
                itemCount: state.groupOrder.length,
                onReorder: (oldIndex, newIndex) => cubit.reorderGroups(
                  oldIndex,
                  // ReorderableListView reports the *insertion* index, which is
                  // one too high when dragging downwards.
                  newIndex > oldIndex ? newIndex - 1 : newIndex,
                ),
                itemBuilder: (context, index) {
                  final id = state.groupOrder[index];
                  final group = toolbarGroupById(id);
                  final visible = index < state.visibleGroupCount;
                  return ListTile(
                    key: AppKeys.mobileToolbarGroupTile(id),
                    leading: Icon(
                      visible ? Icons.visibility : Icons.visibility_off,
                      color: visible
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    title: Text(toolbarGroupLabel(id, l10n)),
                    subtitle: group == null
                        ? null
                        : Text(group.keys.map((k) => k.label).join('  ')),
                    trailing: const Icon(Icons.drag_handle),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The keys this user actually presses, so reordering is informed by data.
class _MostUsed extends StatelessWidget {
  const _MostUsed({required this.keys});

  final List<ToolbarKey> keys;

  @override
  Widget build(BuildContext context) {
    final spacing = context.tpSpacing;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.lg, 0, spacing.lg, spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.mobileToolbarMostUsed, style: styles.mdMedium),
          SizedBox(height: spacing.sm),
          Wrap(
            spacing: spacing.sm,
            runSpacing: spacing.sm,
            children: [
              for (final key in keys)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.sm,
                      vertical: spacing.xs,
                    ),
                    child: Text(key.label, style: styles.smMedium),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
```

Tokens used above are verified to exist: `TpTextStyles.mdMedium` / `.smMedium` / `.sm` (`shared_ui/lib/src/theme/tp_text_styles.dart:124,128,177`) and `TpSpacing.xs/sm/md/lg` (`tokens/tp_spacing.dart:20-26`). Do not add new tokens for this page.

- [ ] **Step 6: Add the gear button to the toolbar**

In `client/lib/pages/pairing/mobile_toolbar/mobile_keyboard_toolbar.dart`, add the import:

```dart
import 'mobile_toolbar_customize_page.dart';
```

and insert this immediately before the `TpIconButton` with key `AppKeys.mobileToolbarHideKeyboardButton`:

```dart
              TpIconButton(
                key: AppKeys.mobileToolbarCustomizeButton,
                icon: Icons.tune,
                tooltip: context.l10n.mobileToolbarCustomize,
                size: barHeight,
                onTap: () => Navigator.of(context).push(
                  MobileToolbarCustomizePage.route(
                    context.read<MobileToolbarCubit>(),
                  ),
                ),
              ),
```

- [ ] **Step 7: Run the tests**

Run: `cd client && flutter test test/pages/pairing/mobile_toolbar_customize_page_test.dart test/pages/pairing/mobile_keyboard_toolbar_test.dart`
Expected: PASS, 9 tests.

- [ ] **Step 8: Full gate**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1 | tail -3`
Expected: no `error •` lines.

Run: `cd client && flutter test --exclude-tags integration 2>&1 | tail -5`
Expected: only the two known pre-existing failures.

- [ ] **Step 9: Commit**

```bash
cd /Users/yitouxiaomaolv/git/cmux
git add client/lib/pages/pairing/mobile_toolbar/ \
        client/lib/utils/ui/app_keys.dart \
        client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
        client/lib/widgets/warmup_glyphs.g.dart \
        client/test/pages/pairing/mobile_toolbar_customize_page_test.dart
git commit -m "feat(mobile): let users reorder and reveal toolbar key groups"
```

---

## Done when

- The pairing mirror shows a 44px key bar; Esc / Tab / arrows / signals reach the desktop PTY.
- Ctrl and Alt are one-shot, mutually exclusive, and rewrite escape sequences with xterm modifiers.
- Holding an arrow repeats; Paste normalizes newlines to CR.
- Group order and visible count survive an app restart; usage counts drive the most-used list.
- `flutter analyze` clean, `flutter test --exclude-tags integration` green except the two known pre-existing failures.

## Deviations from the spec (all deliberate, all recorded)

1. `AppKeys.pairingMirrorCtrlCButton` is deleted rather than moved onto the `^C` cap — one widget takes one key, and every cap needs `mobileToolbarKey(id)`. No source or test outside `app_keys.dart` referenced it.
2. The customize entry is a gear button in the toolbar, not a row in `mobile_settings_sheet.dart`: that sheet hangs off the paired-hosts page where no `MobileToolbarCubit` exists. Nexterm likewise keeps the entry next to the toolbar.
3. Corrupt persisted JSON falls back to defaults silently instead of logging through `AppLogger`. The repository is a pure `shared_preferences` wrapper with no logger dependency, and the fallback is not user-visible. Add logging only if a real report needs it.
4. `pairingSendCtrlC` is retired along with `pairingMirrorInputHint`; the 44px bar has no room for hint text and `^C` is now a labelled cap rather than a tooltipped icon.
