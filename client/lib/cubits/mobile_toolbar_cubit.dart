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
