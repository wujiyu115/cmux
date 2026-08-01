# Mobile Composer Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the mobile pairing mirror a multi-line composer panel that shares the bottom slot with the existing shortcut-key bar: edit a command locally, send it in one go, optionally without a trailing Return.

**Architecture:** Three layers, all already established by subproject A. `MobileToolbarCubit` grows a `MobileInputMode` (keys ↔ composer), a non-persisted `chatMode` flag, and a `sendText` method that encodes text the same way paste does. The panel is a route-only widget under `client/lib/pages/pairing/mobile_toolbar/`. The draft `TextEditingController` and `FocusNode` are owned by `_PairingMirrorPageState`, so switching panels keeps the text but leaving the page discards it — and typing never emits cubit state.

**Tech Stack:** Flutter 3.29 / Dart 3, `flutter_bloc`, `flutter_test` (no `bloc_test` in this repo — do not add it).

**Spec:** `docs/superpowers/specs/2026-08-01-mobile-composer-design.md`

## Global Constraints

- Work from `/Users/yitouxiaomaolv/git/cmux/client`. All `flutter` commands run there.
- Gate before claiming any task done: `flutter analyze --no-fatal-infos --no-fatal-warnings` (0 errors, no new warnings) and the task's own test files pass.
- Two pre-existing test failures are NOT yours and must not be "fixed": `test/pages/command_palette/command_palette_overlay_test.dart` (chord badge) and `test/services/terminal/pty_launch_environment_test.dart` (TERM_PROGRAM).
- State management is `flutter_bloc` only. Never `provider`, never `setState` for state another widget reads.
- All user-facing strings go in BOTH `lib/l10n/app_en.arb` and `lib/l10n/app_zh.arb`, read via `context.l10n.<key>`.
- After editing an ARB run `dart run tool/gen_warmup_glyphs.dart`; if the generated `AppLocalizations` lags behind the ARB (it happened once in subproject A), run `flutter gen-l10n`.
- Colors come from `Theme.of(context).colorScheme` — this repo has no palette extension with `accent`/`border`/`fg` names.
- Widget tests that render localized UI must wrap `MaterialApp` with `AppLocalizations.localizationsDelegates` + `supportedLocales` + `locale: const Locale('en')`.
- Widget test keys live in `lib/utils/ui/app_keys.dart` as `static const x = Key('kebab-name')`.
- The repo has unrelated uncommitted changes (`client/ios/` xcconfig / pbxproj / Podfile). Never `git add -A` or `git add .` — stage only the paths each task names.
- `MobileToolbarState` has NO value equality and its constructor is NOT const: every emit is a distinct instance, so any `BlocBuilder` you add needs a `buildWhen` naming the fields it draws.
- `MobileToolbarState.groupOrder` / `.usage` are unmodifiable views — never sort or mutate them in place.
- No `print`; diagnostics go through `AppLogger`. Doc comments explain why, not what.
- File size soft caps: cubits ~500 lines, page shells ~400.
- Commit after every task with the exact message given in the task's final step.

## File Structure

| File | Responsibility |
|---|---|
| `lib/cubits/mobile_toolbar_cubit.dart` (modify) | Add `enum MobileInputMode`, `state.mode`, `state.chatMode`, `setMode`, `toggleComposer`, `toggleChatMode`, `sendText`. |
| `lib/pages/pairing/mobile_toolbar/mobile_composer_panel.dart` (create) | Panel UI: capped multi-line field + five circular buttons. Requests focus when it mounts. No IO, no pairing knowledge. |
| `lib/pages/pairing/mobile_toolbar/mobile_keyboard_toolbar.dart` (modify) | Bubble button that switches the bottom slot to the composer. |
| `lib/pages/pairing/pairing_mirror_page.dart` (modify) | Owns the draft controller + focus node; renders bar or panel by `state.mode`. |
| `lib/utils/ui/app_keys.dart` (modify) | Composer widget keys. |
| `lib/l10n/app_en.arb`, `app_zh.arb` (modify) | Six strings. |

---

### Task 1: Cubit — input mode, Return-mode, `sendText`

**Files:**
- Modify: `client/lib/cubits/mobile_toolbar_cubit.dart`
- Test: `client/test/cubits/mobile_toolbar_cubit_test.dart` (append a new group)

**Interfaces:**
- Consumes: `terminalizeNewlines(String)` from `lib/services/terminal/toolbar_key_encoder.dart`; `sanitizeToolbarPrefs`, `MobileToolbarPrefs` from `lib/repositories/mobile_toolbar_repository.dart`; `InMemoryMobileToolbarRepository` in tests.
- Produces: `enum MobileInputMode { keys, composer }`; `MobileToolbarState.mode` (default `MobileInputMode.keys`), `MobileToolbarState.chatMode` (default `true`), both threaded through `copyWith`; `void setMode(MobileInputMode mode)`, `void toggleComposer()`, `void toggleChatMode()`, `void sendText(String text, {required bool submit})`.

- [ ] **Step 1: Write the failing tests**

Append to `client/test/cubits/mobile_toolbar_cubit_test.dart`, inside `void main() { ... }` after the existing tests (reuse the file's existing `sent`, `repo`, `build`, and `key` helpers):

```dart
  group('composer', () {
    test('starts in key mode with Return-mode on', () async {
      final cubit = build();
      expect(cubit.state.mode, MobileInputMode.keys);
      expect(cubit.state.chatMode, isTrue);
      await cubit.close();
    });

    test('toggleComposer flips between the two panels', () async {
      final cubit = build();
      cubit.toggleComposer();
      expect(cubit.state.mode, MobileInputMode.composer);
      cubit.toggleComposer();
      expect(cubit.state.mode, MobileInputMode.keys);
      await cubit.close();
    });

    test('setMode to the current mode does not emit', () async {
      final cubit = build();
      final seen = <MobileInputMode>[];
      final sub = cubit.stream.listen((s) => seen.add(s.mode));
      cubit.setMode(MobileInputMode.keys);
      await Future<void>.delayed(Duration.zero);
      expect(seen, isEmpty);
      cubit.setMode(MobileInputMode.composer);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [MobileInputMode.composer]);
      await sub.cancel();
      await cubit.close();
    });

    test('toggleChatMode flips the flag', () async {
      final cubit = build();
      cubit.toggleChatMode();
      expect(cubit.state.chatMode, isFalse);
      cubit.toggleChatMode();
      expect(cubit.state.chatMode, isTrue);
      await cubit.close();
    });

    test('sendText appends CR only when submitting', () async {
      final cubit = build();
      cubit.sendText('ls', submit: true);
      cubit.sendText('ls', submit: false);
      expect(sent, [
        [0x6c, 0x73, 0x0d],
        [0x6c, 0x73],
      ]);
      await cubit.close();
    });

    test('sendText rewrites newlines to CR so each line runs', () async {
      final cubit = build();
      cubit.sendText('a\nb', submit: false);
      expect(String.fromCharCodes(sent.single), 'a\rb');
      await cubit.close();
    });

    test('empty text sends a bare CR when submitting, nothing otherwise', () async {
      final cubit = build();
      cubit.sendText('', submit: false);
      expect(sent, isEmpty);
      cubit.sendText('', submit: true);
      expect(sent, [[0x0d]]);
      await cubit.close();
    });

    test('whitespace is real input, not emptiness', () async {
      final cubit = build();
      cubit.sendText('  ', submit: false);
      expect(sent, [[0x20, 0x20]]);
      await cubit.close();
    });

    test('sendText ignores modifiers and does not consume them', () async {
      final cubit = build();
      await cubit.tapKey(key('ctrl'));
      cubit.sendText('a', submit: false);
      expect(sent, [[0x61]], reason: 'Ctrl must not mask composer text');
      expect(cubit.state.ctrl, isTrue, reason: 'and must survive the send');
      expect(cubit.state.usage, isEmpty, reason: 'text is not a key tap');
      await cubit.close();
    });

    test('sent bytes are unmodifiable', () async {
      final cubit = build();
      cubit.sendText('a', submit: true);
      expect(() => sent.single.add(0x00), throwsUnsupportedError);
      await cubit.close();
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd client && flutter test test/cubits/mobile_toolbar_cubit_test.dart`
Expected: FAIL — `Error: Undefined name 'MobileInputMode'` / `The method 'sendText' isn't defined`.

- [ ] **Step 3: Add the enum and the two state fields**

In `client/lib/cubits/mobile_toolbar_cubit.dart`, insert above `class MobileToolbarState`:

```dart
/// Which panel occupies the mirror page's bottom slot.
enum MobileInputMode { keys, composer }
```

In `MobileToolbarState`, add the two parameters to the primary constructor (after `this.alt = false,`):

```dart
    this.mode = MobileInputMode.keys,
    this.chatMode = true,
```

Add the fields after `final bool alt;`:

```dart
  /// Which bottom panel is showing. Not persisted: a session starts on the keys.
  final MobileInputMode mode;

  /// Whether [MobileToolbarCubit.sendText] appends CR. Not persisted — every
  /// launch returns to "Return submits", the behavior that matches the terminal.
  final bool chatMode;
```

Extend `copyWith`'s signature with:

```dart
    MobileInputMode? mode,
    bool? chatMode,
```

and its body with:

```dart
    mode: mode ?? this.mode,
    chatMode: chatMode ?? this.chatMode,
```

- [ ] **Step 4: Add the four methods**

In `MobileToolbarCubit`, insert after `void toggleAlt() => ...`:

```dart
  void setMode(MobileInputMode mode) {
    // Re-emitting the same mode would rebuild the whole bottom slot, which
    // rebuilds the composer and drops the soft keyboard mid-typing.
    if (mode == state.mode) return;
    emit(state.copyWith(mode: mode));
  }

  void toggleComposer() => setMode(
    state.mode == MobileInputMode.composer
        ? MobileInputMode.keys
        : MobileInputMode.composer,
  );

  void toggleChatMode() => emit(state.copyWith(chatMode: !state.chatMode));

  /// Sends composer text as PTY input.
  ///
  /// Like [_paste] and unlike [tapKey], this is raw text: modifiers neither
  /// apply nor get consumed, and it earns no usage count. Newlines become CR so
  /// every line actually runs.
  ///
  /// Empty text with [submit] sends a bare CR — the sixteen key groups contain
  /// no Enter, so this is the only Enter the mobile UI has that does not depend
  /// on the soft keyboard. Empty text without [submit] sends nothing.
  void sendText(String text, {required bool submit}) {
    if (text.isEmpty) {
      if (submit) _sendInput(List.unmodifiable(const [0x0d]));
      return;
    }
    final bytes = utf8.encode(terminalizeNewlines(text));
    _sendInput(List.unmodifiable(submit ? [...bytes, 0x0d] : bytes));
  }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd client && flutter test test/cubits/mobile_toolbar_cubit_test.dart`
Expected: PASS — the 10 new tests plus every pre-existing one in the file.

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/cubits/mobile_toolbar_cubit.dart test/cubits/mobile_toolbar_cubit_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd /Users/yitouxiaomaolv/git/cmux
git add client/lib/cubits/mobile_toolbar_cubit.dart client/test/cubits/mobile_toolbar_cubit_test.dart
git commit -m "feat(mobile): teach the toolbar cubit to send composer text"
```

---

### Task 2: The composer panel

**Files:**
- Create: `client/lib/pages/pairing/mobile_toolbar/mobile_composer_panel.dart`
- Modify: `client/lib/utils/ui/app_keys.dart` (after `mobileToolbarGroupTile`)
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/pairing/mobile_composer_panel_test.dart`

**Interfaces:**
- Consumes: `MobileToolbarCubit` (`sendText`, `toggleChatMode`, `setMode`), `MobileToolbarState.chatMode`, `MobileInputMode` (Task 1).
- Produces: `class MobileComposerPanel extends StatefulWidget` with `const MobileComposerPanel({super.key, required TextEditingController controller, required FocusNode focusNode})`; `AppKeys.mobileComposerPanel`, `.mobileComposerField`, `.mobileComposerSendButton`, `.mobileComposerCloseButton`, `.mobileComposerSubmitToggle`, `.mobileToolbarComposerButton`.

- [ ] **Step 1: Add the strings and keys**

Append to `client/lib/l10n/app_en.arb` before the closing `}` (comma after the previous last entry):

```json
  "mobileComposerHint": "Type a command",
  "mobileComposerOpen": "Compose text",
  "mobileComposerClose": "Close composer",
  "mobileComposerSend": "Send",
  "mobileComposerSubmitOn": "Send with Return",
  "mobileComposerSubmitOff": "Send without Return"
```

Append the same keys to `client/lib/l10n/app_zh.arb`:

```json
  "mobileComposerHint": "输入命令",
  "mobileComposerOpen": "文本输入",
  "mobileComposerClose": "关闭输入面板",
  "mobileComposerSend": "发送",
  "mobileComposerSubmitOn": "发送时回车",
  "mobileComposerSubmitOff": "发送不回车"
```

In `client/lib/utils/ui/app_keys.dart`, add after the `mobileToolbarGroupTile` helper:

```dart
  static const mobileToolbarComposerButton = Key('mobile-toolbar-composer');
  static const mobileComposerPanel = Key('mobile-composer-panel');
  static const mobileComposerField = Key('mobile-composer-field');
  static const mobileComposerSendButton = Key('mobile-composer-send');
  static const mobileComposerCloseButton = Key('mobile-composer-close');
  static const mobileComposerSubmitToggle = Key('mobile-composer-submit');
```

Run: `cd client && dart run tool/gen_warmup_glyphs.dart`
Then confirm the generated getters exist: `rg -c 'mobileComposer' lib/l10n/app_localizations.dart`
Expected: a non-zero count. If it is zero or short, run `flutter gen-l10n` and re-check.

- [ ] **Step 2: Write the failing test**

Create `client/test/pages/pairing/mobile_composer_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/mobile_toolbar_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/pairing/mobile_toolbar/mobile_composer_panel.dart';
import 'package:teampilot/repositories/mobile_toolbar_repository.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

void main() {
  late List<List<int>> sent;
  late MobileToolbarCubit cubit;
  late TextEditingController controller;
  late FocusNode focusNode;

  setUp(() {
    sent = [];
    cubit = MobileToolbarCubit(
      repository: InMemoryMobileToolbarRepository(),
      sendInput: sent.add,
      readClipboard: () async => null,
      usageFlushDelay: const Duration(milliseconds: 10),
    );
    cubit.setMode(MobileInputMode.composer);
    controller = TextEditingController();
    focusNode = FocusNode();
  });

  tearDown(() async {
    await cubit.close();
    controller.dispose();
    focusNode.dispose();
  });

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
                child: MobileComposerPanel(
                  controller: controller,
                  focusNode: focusNode,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders the field and its four controls', (t) async {
    await pump(t);
    expect(find.byKey(AppKeys.mobileComposerPanel), findsOneWidget);
    expect(find.text('Type a command'), findsOneWidget);
    for (final key in [
      AppKeys.mobileComposerField,
      AppKeys.mobileComposerSendButton,
      AppKeys.mobileComposerCloseButton,
      AppKeys.mobileComposerSubmitToggle,
    ]) {
      expect(find.byKey(key), findsOneWidget);
    }
  });

  testWidgets('takes focus when it mounts so the keyboard opens', (t) async {
    await pump(t);
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('send appends CR and clears the draft', (t) async {
    await pump(t);
    await t.enterText(find.byKey(AppKeys.mobileComposerField), 'ls -la');
    await t.tap(find.byKey(AppKeys.mobileComposerSendButton));
    await t.pump();
    expect(String.fromCharCodes(sent.single), 'ls -la\r');
    expect(controller.text, isEmpty);
  });

  testWidgets('Return-mode off sends the text bare', (t) async {
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerSubmitToggle));
    await t.pump();
    await t.enterText(find.byKey(AppKeys.mobileComposerField), 'ls -la');
    await t.tap(find.byKey(AppKeys.mobileComposerSendButton));
    await t.pump();
    expect(String.fromCharCodes(sent.single), 'ls -la');
    expect(cubit.state.chatMode, isFalse);
  });

  testWidgets('send with an empty draft presses Return', (t) async {
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerSendButton));
    await t.pump();
    expect(sent, [[0x0d]]);
  });

  testWidgets('close returns the bottom slot to the key bar', (t) async {
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerCloseButton));
    await t.pump();
    expect(cubit.state.mode, MobileInputMode.keys);
  });

  testWidgets('the draft is not owned by the panel', (t) async {
    await pump(t);
    await t.enterText(find.byKey(AppKeys.mobileComposerField), 'half typed');
    // Unmounting the panel is what happens when the user switches to the key
    // bar; the caller's controller must survive it.
    await t.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(controller.text, 'half typed');
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd client && flutter test test/pages/pairing/mobile_composer_panel_test.dart`
Expected: FAIL — `Error: Couldn't resolve … mobile_composer_panel.dart`.

- [ ] **Step 4: Write the panel**

Create `client/lib/pages/pairing/mobile_toolbar/mobile_composer_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/mobile_toolbar_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../utils/ui/app_keys.dart';

/// Multi-line composer for the mirrored terminal.
///
/// Typing straight into a terminal over a phone keyboard is unforgiving — the
/// PTY echoes every character and a typo means retyping the line. Here the text
/// is local until the send button, so it can be edited, and Return inserts a
/// newline instead of submitting (the deliberate opposite of the terminal, where
/// Return submits).
///
/// [controller] and [focusNode] belong to the caller: the panel is unmounted
/// whenever the user flips to the key bar, and the draft has to survive that.
class MobileComposerPanel extends StatefulWidget {
  const MobileComposerPanel({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  static const double _buttonSize = 34;
  static const double _fieldMaxHeight = 120;

  @override
  State<MobileComposerPanel> createState() => _MobileComposerPanelState();
}

class _MobileComposerPanelState extends State<MobileComposerPanel> {
  @override
  void initState() {
    super.initState();
    // Taking focus here also drops the terminal's own IME client, so the two
    // never fight over the single soft keyboard.
    widget.focusNode.requestFocus();
  }

  void _send(bool submit) {
    context.read<MobileToolbarCubit>().sendText(
      widget.controller.text,
      submit: submit,
    );
    widget.controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final cubit = context.read<MobileToolbarCubit>();
    return DecoratedBox(
      key: AppKeys.mobileComposerPanel,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: MobileComposerPanel._fieldMaxHeight,
                ),
                child: Scrollbar(
                  child: TextField(
                    key: AppKeys.mobileComposerField,
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    style: TextStyle(color: cs.onSurface, fontSize: 15),
                    minLines: 3,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: l10n.mobileComposerHint,
                      hintStyle: TextStyle(color: cs.onSurfaceVariant),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              BlocBuilder<MobileToolbarCubit, MobileToolbarState>(
                // Only the Return-mode flag changes anything in this row, and
                // the state re-emits on every key tap.
                buildWhen: (before, after) =>
                    before.chatMode != after.chatMode,
                builder: (context, state) => Row(
                  children: [
                    _CircleButton(
                      buttonKey: AppKeys.mobileComposerCloseButton,
                      icon: Icons.close,
                      tooltip: l10n.mobileComposerClose,
                      onTap: () {
                        // Drop the keyboard before the field disappears —
                        // otherwise the focus node stays focused with no
                        // TextField mounted and the keyboard hangs around over
                        // the key bar.
                        FocusScope.of(context).unfocus();
                        cubit.setMode(MobileInputMode.keys);
                      },
                    ),
                    const SizedBox(width: 8),
                    _CircleButton(
                      icon: Icons.keyboard_hide,
                      tooltip: l10n.mobileToolbarHideKeyboard,
                      onTap: () => FocusScope.of(context).unfocus(),
                    ),
                    const SizedBox(width: 8),
                    _CircleButton(
                      buttonKey: AppKeys.mobileComposerSubmitToggle,
                      icon: state.chatMode
                          ? Icons.keyboard_return
                          : Icons.text_fields,
                      tooltip: state.chatMode
                          ? l10n.mobileComposerSubmitOn
                          : l10n.mobileComposerSubmitOff,
                      filled: state.chatMode,
                      onTap: cubit.toggleChatMode,
                    ),
                    const Spacer(),
                    _CircleButton(
                      buttonKey: AppKeys.mobileComposerSendButton,
                      icon: Icons.arrow_upward,
                      tooltip: l10n.mobileComposerSend,
                      filled: true,
                      onTap: () => _send(state.chatMode),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round variant of [TpIconButton] — the composer's controls read as chips
/// rather than as toolbar squares.
class _CircleButton extends StatelessWidget {
  const _CircleButton({
    this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.filled = false,
  });

  final Key? buttonKey;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TpIconButton(
      key: buttonKey,
      icon: icon,
      tooltip: tooltip,
      onTap: onTap,
      size: MobileComposerPanel._buttonSize,
      iconSize: 18,
      borderRadius: MobileComposerPanel._buttonSize / 2,
      color: filled ? cs.onPrimary : cs.onSurfaceVariant,
      backgroundColor: filled ? cs.primary : cs.surfaceContainerHighest,
    );
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd client && flutter test test/pages/pairing/mobile_composer_panel_test.dart`
Expected: PASS, 7 tests.

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/pairing/mobile_toolbar/ lib/utils/ui/app_keys.dart test/pages/pairing/mobile_composer_panel_test.dart`
Expected: no `error` or `warning` lines (one pre-existing `deprecated_member_use` info about `onReorder` in `mobile_toolbar_customize_page.dart` is expected and not yours).

- [ ] **Step 6: Commit**

```bash
cd /Users/yitouxiaomaolv/git/cmux
git add client/lib/pages/pairing/mobile_toolbar/mobile_composer_panel.dart \
        client/lib/utils/ui/app_keys.dart \
        client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
        client/lib/l10n/app_localizations.dart \
        client/lib/l10n/app_localizations_en.dart \
        client/lib/l10n/app_localizations_zh.dart \
        client/lib/widgets/warmup_glyphs.g.dart \
        client/test/pages/pairing/mobile_composer_panel_test.dart
git commit -m "feat(mobile): add a multi-line composer panel for the mirrored terminal"
```

If `git status` shows `warmup_glyphs.g.dart` unchanged (the new strings introduced no new glyphs), drop it from the `git add` list rather than forcing it.

---

### Task 3: Wire the two panels into the mirror page

**Files:**
- Modify: `client/lib/pages/pairing/pairing_mirror_page.dart`
- Modify: `client/lib/pages/pairing/mobile_toolbar/mobile_keyboard_toolbar.dart`
- Test: `client/test/pages/pairing/mobile_keyboard_toolbar_test.dart` (append one test)

**Interfaces:**
- Consumes: `MobileComposerPanel({required controller, required focusNode})` (Task 2); `MobileInputMode`, `MobileToolbarCubit.toggleComposer`, `MobileToolbarState.mode` (Task 1); `AppKeys.mobileToolbarComposerButton` (Task 2).
- Produces: nothing later tasks depend on — this is the last task of subproject B.

- [ ] **Step 1: Write the failing test**

Append inside `void main() { ... }` of `client/test/pages/pairing/mobile_keyboard_toolbar_test.dart`:

```dart
  testWidgets('the bubble button switches the bottom slot to the composer', (
    t,
  ) async {
    await pump(t);
    expect(cubit.state.mode, MobileInputMode.keys);
    await t.tap(find.byKey(AppKeys.mobileToolbarComposerButton));
    await t.pump();
    expect(cubit.state.mode, MobileInputMode.composer);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && flutter test test/pages/pairing/mobile_keyboard_toolbar_test.dart`
Expected: FAIL — the `mobileToolbarComposerButton` finder matches nothing ("Found 0 widgets with key").

- [ ] **Step 3: Add the bubble button to the bar**

In `client/lib/pages/pairing/mobile_toolbar/mobile_keyboard_toolbar.dart`, insert immediately before the `TpIconButton` whose key is `AppKeys.mobileToolbarCustomizeButton`:

```dart
              TpIconButton(
                key: AppKeys.mobileToolbarComposerButton,
                icon: Icons.chat_bubble_outline,
                tooltip: context.l10n.mobileComposerOpen,
                size: barHeight,
                onTap: context.read<MobileToolbarCubit>().toggleComposer,
              ),
```

The button carries no active tint: the bar is only mounted in `MobileInputMode.keys`, so a "composer is open" state could never render here — the spec's tinted-bubble note applied to Nexterm's always-visible bar.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd client && flutter test test/pages/pairing/mobile_keyboard_toolbar_test.dart`
Expected: PASS — the new test plus the five pre-existing ones.

- [ ] **Step 5: Own the draft in the mirror page and render by mode**

In `client/lib/pages/pairing/pairing_mirror_page.dart`, add to the imports:

```dart
import 'mobile_toolbar/mobile_composer_panel.dart';
```

Add these fields next to `late final MobileToolbarCubit _toolbar;`:

```dart
  /// The composer's draft outlives the panel: flipping to the key bar unmounts
  /// the panel, and the half-typed command has to still be there on the way
  /// back. It dies with the page, which is why it is not persisted.
  final _composerText = TextEditingController();
  final _composerFocus = FocusNode();
```

In `dispose`, before `_toolbar.close();`:

```dart
    _composerText.dispose();
    _composerFocus.dispose();
```

Replace the bottom-slot child — currently

```dart
              BlocProvider.value(
                value: _toolbar,
                child: const MobileKeyboardToolbar(),
              ),
```

with

```dart
              BlocProvider.value(
                value: _toolbar,
                child: BlocBuilder<MobileToolbarCubit, MobileToolbarState>(
                  // The state re-emits on every key tap; only the mode decides
                  // which panel is mounted.
                  buildWhen: (before, after) => before.mode != after.mode,
                  builder: (context, state) => switch (state.mode) {
                    MobileInputMode.keys => const MobileKeyboardToolbar(),
                    MobileInputMode.composer => MobileComposerPanel(
                      controller: _composerText,
                      focusNode: _composerFocus,
                    ),
                  },
                ),
              ),
```

- [ ] **Step 6: Run the full gate**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1 | tail -3`
Expected: 0 `error •` lines; the only info in the toolbar directory is the pre-existing `onReorder` deprecation.

Run: `cd client && flutter test --exclude-tags integration -r compact 2>&1 | tail -3`
Expected: only the two known pre-existing failures named in Global Constraints.

- [ ] **Step 7: Commit**

```bash
cd /Users/yitouxiaomaolv/git/cmux
git add client/lib/pages/pairing/pairing_mirror_page.dart \
        client/lib/pages/pairing/mobile_toolbar/mobile_keyboard_toolbar.dart \
        client/test/pages/pairing/mobile_keyboard_toolbar_test.dart
git commit -m "feat(mobile): swap the mirror's bottom slot between keys and composer"
```

---

## Done when

- The bar's bubble button opens the composer; the composer's close button returns to the bar.
- A typed command reaches the host PTY with a trailing CR, and without one when Return-mode is off.
- An empty send presses Return.
- A half-typed draft survives flipping to the key bar and back, and is gone after leaving the mirror.
- `flutter analyze` clean; `flutter test --exclude-tags integration` green except the two known pre-existing failures.

## Deviations from the spec, deliberate

1. The bar's bubble button has no active tint (see Task 3, Step 3): the bar is never mounted while the composer is open.
2. Focus is requested in the panel's `initState` rather than by a post-frame callback in the page — same effect, and it keeps the page from knowing about the panel's focus lifecycle.
