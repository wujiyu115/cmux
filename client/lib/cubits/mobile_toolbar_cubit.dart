import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/toolbar_key.dart';
import '../repositories/mobile_toolbar_repository.dart';
import '../services/terminal/toolbar_key_encoder.dart';
import '../utils/logging/logger_utils.dart';

@immutable
class MobileToolbarState {
  /// Copies the collections into unmodifiable views, matching
  /// [MobileToolbarPrefs]: `state.groupOrder` is handed straight to
  /// `ReorderableListView` and `state.usage` to the customize page, and an
  /// in-place `sort` / `removeAt` there would rewrite live state behind
  /// [Cubit.emit]'s back — no rebuild, and the next `copyWith` would carry the
  /// corruption forward.
  MobileToolbarState({
    required List<String> groupOrder,
    required this.visibleGroupCount,
    required Map<String, int> usage,
    this.ctrl = false,
    this.alt = false,
  }) : groupOrder = List.unmodifiable(groupOrder),
       usage = Map.unmodifiable(usage);

  MobileToolbarState.fromPrefs(MobileToolbarPrefs prefs)
    : this(
        groupOrder: prefs.groupOrder,
        visibleGroupCount: prefs.visibleGroupCount,
        usage: prefs.usage,
      );

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
///
/// No `==` / `hashCode`: every emit is a distinct instance, so a plain
/// `BlocBuilder` rebuilds on every keypress (each tap bumps `usage`). Widgets
/// that only care about layout should use `buildWhen` / `BlocSelector`.
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

  /// Receives the PTY bytes for one key tap.
  ///
  /// The callback must neither retain nor mutate the list it is handed: the
  /// bytes may be an entry of the module-global key table (see
  /// [encodeToolbarKey]'s pass-through), so it is passed as an unmodifiable view
  /// and a retained reference would alias a shared, possibly-replaced buffer.
  final void Function(List<int> bytes) _sendInput;
  final Future<String?> Function() _readClipboard;

  /// Tap counters change on every key press; coalesce them so a burst of arrow
  /// repeats is one disk write, not eighty.
  final Duration usageFlushDelay;
  Timer? _usageFlush;

  /// The debounced write currently in flight, so [close] can wait for it instead
  /// of racing it.
  Future<void>? _pendingUsageSave;

  Future<void> load() async {
    final prefs = await _repository.load();
    // Callers fire load() and forget it, so popping the page mid-load would
    // otherwise emit on a closed cubit and throw StateError.
    if (isClosed) return;
    // [MobileToolbarRepository] is an interface: re-sanitize so a third
    // implementation cannot seat an out-of-range visibleGroupCount or an
    // unknown group id in live state.
    emit(
      MobileToolbarState.fromPrefs(
        sanitizeToolbarPrefs(
          groupOrder: prefs.groupOrder,
          visibleGroupCount: prefs.visibleGroupCount,
          usage: prefs.usage,
        ),
      ),
    );
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
    if (bytes.isEmpty) {
      // A modifier armed for a key that turns out to emit nothing must still be
      // consumed, or it would silently apply to whatever the user taps next.
      _clearModifiers();
      return;
    }
    _sendInput(List.unmodifiable(bytes));
    _countTap(key.id);
  }

  /// Paste is raw text, so modifiers do not apply and it earns no usage count
  /// (Nexterm parity). Newlines become CR or the shell never runs the line.
  Future<void> _paste() async {
    final text = await _readClipboard();
    if (text == null || text.isEmpty) return;
    _sendInput(List.unmodifiable(utf8.encode(terminalizeNewlines(text))));
  }

  Future<void> setVisibleGroupCount(int count) => _persist(
    sanitizeToolbarPrefs(
      groupOrder: state.groupOrder,
      visibleGroupCount: count,
      usage: state.usage,
    ),
  );

  /// Moves the group at [oldIndex] to [newIndex], where [newIndex] is the index
  /// **after** the moved element has been removed.
  ///
  /// `ReorderableListView.onReorder` reports a **pre**-removal index, so the call
  /// site must normalize: `reorderGroups(o, n > o ? n - 1 : n)`. The two
  /// conventions coincide for upward moves, which is why getting this wrong only
  /// shows up when the user drags a group downward.
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
    emit(
      state.copyWith(
        groupOrder: prefs.groupOrder,
        visibleGroupCount: prefs.visibleGroupCount,
        usage: prefs.usage,
      ),
    );
    _usageFlush?.cancel();
    _usageFlush = null;
    await _repository.save(prefs);
  }

  void _clearModifiers() {
    if (state.ctrl || state.alt) emit(state.copyWith(ctrl: false, alt: false));
  }

  /// One emit for the whole tap: bumping usage and clearing the modifiers
  /// separately would publish an intermediate state where the key has already
  /// been sent but Ctrl still reads pressed, flashing the key cap as active.
  void _countTap(String keyId) {
    final usage = {...state.usage};
    usage[keyId] = (usage[keyId] ?? 0) + 1;
    emit(state.copyWith(usage: usage, ctrl: false, alt: false));
    _usageFlush?.cancel();
    _usageFlush = Timer(usageFlushDelay, _flushUsage);
  }

  void _flushUsage() {
    _usageFlush = null;
    // A Timer callback has no caller to return the future to, so an unguarded
    // rejection escapes as an uncaught async error.
    //
    // Deliberately NOT awaited by close(): this future is created in whatever
    // zone drove the timer, and a widget test's fake clock stops advancing once
    // the test body ends — awaiting it from tearDown deadlocks until the 10
    // minute test timeout. Nothing can change the counts between this write
    // firing and close(), so the in-flight write already carries the final
    // state and losing the await costs no data.
    _pendingUsageSave = _repository.save(state.prefs).catchError(_reportFailure);
  }

  void _reportFailure(Object error, StackTrace stackTrace) {
    AppLogger.instance.w(
      'Failed to persist mobile toolbar usage counts ($error)',
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  Future<void> close() async {
    try {
      final pending = _usageFlush;
      _usageFlush = null;
      if (pending != null) {
        // Only a write this call issues is awaited — it is created in the
        // caller's zone, so it can actually complete. See [_flushUsage] for why
        // an already-airborne write is left alone.
        pending.cancel();
        _pendingUsageSave = _repository.save(state.prefs);
        await _pendingUsageSave;
      }
    } on Object catch (error, stackTrace) {
      // A failed final write must not stop the cubit from closing: BlocProvider
      // disposal does not expect close() to throw, and skipping super.close()
      // would leak the state stream controller.
      _reportFailure(error, stackTrace);
    } finally {
      await super.close();
    }
  }
}
