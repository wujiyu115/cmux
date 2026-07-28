import 'dart:async';

import 'package:shared_ui/shared_ui.dart';

import '../../models/app_notification.dart';
import '../../utils/terminal/osc_sequence_scanner.dart';
import '../notification/notification_recorder.dart';

/// Terminal-emitted desktop notifications → the app notification center.
///
/// Two feeds, because the engine only decodes some of the escapes:
/// * [observeEngineNotify] takes `TerminalEngine.notify` (OSC 9 = body only,
///   OSC 777 = title and body joined by NUL).
/// * [observePtyText] scans raw PTY text for OSC 99 (kitty), which the engine
///   drops on the floor.
///
/// Titles are prefixed with [attribution] so a notification names the workspace
/// / pane it came from; [payload] deep-links back to it.
class TerminalOscNotificationBridge {
  TerminalOscNotificationBridge({
    required this.attribution,
    required this.payload,
    NotificationRecorder? recorder,
  }) : _recorder = recorder ?? NotificationRecorder.maybeCurrent,
       _scanner = OscSequenceScanner(codes: const {osc99Code});

  /// Kitty desktop notification: `ESC ] 99 ; metadata ; payload ST`.
  static const int osc99Code = 99;

  /// Longest notification text kept; the scanner already bounds raw payloads.
  static const int maxBodyChars = 512;

  /// Separator the engine puts between OSC 777's title and body.
  static final String osc777Separator = String.fromCharCode(0);

  /// Resolves the human label to prefix titles with (workspace / pane name).
  /// A closure because pane labels change as the shell reports new titles.
  final String Function() attribution;

  /// Router location recorded on each row (`/home-v2/workspace/{id}`).
  final String Function() payload;

  final NotificationRecorder? _recorder;
  final OscSequenceScanner _scanner;

  /// Pending kitty notifications keyed by their `i=` id, for `d=0` chunking.
  final Map<String, _KittyDraft> _drafts = {};

  StreamSubscription<String>? _engineSub;
  bool _disposed = false;

  /// Subscribe to the engine's OSC 9 / 777 stream.
  void observeEngineNotify(Stream<String> notify) {
    _engineSub?.cancel();
    _engineSub = notify.listen(_onEngineNotify);
  }

  /// Feed decoded PTY text (the same chunks the title extractor sees).
  void observePtyText(String text) {
    if (_disposed || text.isEmpty) return;
    for (final sequence in _scanner.push(text)) {
      _onKitty(sequence.payload);
    }
  }

  void reset() {
    _scanner.reset();
    _drafts.clear();
  }

  void dispose() {
    _disposed = true;
    _engineSub?.cancel();
    _engineSub = null;
    reset();
  }

  // --- OSC 9 / 777 -----------------------------------------------------------

  void _onEngineNotify(String raw) {
    if (_disposed) return;
    final split = raw.indexOf(osc777Separator);
    if (split < 0) {
      // OSC 9 carries a body only.
      _emit(
        source: AppNotificationSource.osc9,
        title: '',
        body: raw,
        variant: TpToastVariant.success,
      );
      return;
    }
    _emit(
      source: AppNotificationSource.osc777,
      title: raw.substring(0, split),
      body: raw.substring(split + osc777Separator.length),
      variant: TpToastVariant.success,
    );
  }

  // --- OSC 99 (kitty) --------------------------------------------------------

  /// [raw] is everything after `ESC ] 99 ;` — `metadata ; payload`, where the
  /// metadata is `key=value` pairs joined by `:` (`i=1:d=0:p=title:u=2`).
  void _onKitty(String raw) {
    final split = raw.indexOf(';');
    final meta = split < 0 ? raw : raw.substring(0, split);
    final body = split < 0 ? '' : raw.substring(split + 1);

    var id = '';
    var part = 'body';
    var done = true;
    var urgency = 1;
    for (final field in meta.split(':')) {
      final eq = field.indexOf('=');
      if (eq <= 0) continue;
      final key = field.substring(0, eq);
      final value = field.substring(eq + 1);
      switch (key) {
        case 'i':
          id = value;
        case 'p':
          part = value;
        case 'd':
          // `d=0` means "more chunks follow"; anything else ends the report.
          done = value != '0';
        case 'u':
          urgency = int.tryParse(value) ?? 1;
      }
    }

    final draft = _drafts.putIfAbsent(id, _KittyDraft.new);
    draft.urgency = urgency;
    switch (part) {
      case 'title':
        draft.title += body;
      case 'body':
        draft.body += body;
      default:
        // Other payload kinds (icons, buttons) are not rendered; ignore them
        // instead of leaking raw bytes into the notification text.
        break;
    }
    if (!done) return;

    _drafts.remove(id);
    // Kitty usually sends only `p=title`; promote it to the body so the row is
    // not an empty message with a headline.
    final hasBody = draft.body.isNotEmpty;
    _emit(
      source: AppNotificationSource.osc99,
      title: hasBody ? draft.title : '',
      body: hasBody ? draft.body : draft.title,
      // u=2 is "critical" in the kitty spec; lower levels stay informational.
      variant: draft.urgency >= 2
          ? TpToastVariant.error
          : TpToastVariant.success,
    );
  }

  // --- shared ----------------------------------------------------------------

  void _emit({
    required AppNotificationSource source,
    required String title,
    required String body,
    required TpToastVariant variant,
  }) {
    final recorder = _recorder;
    if (recorder == null) return;
    final message = _clamp(_sanitize(body));
    if (message.isEmpty) return;
    final label = attribution().trim();
    final oscTitle = _clamp(_sanitize(title));
    final headline = [
      if (label.isNotEmpty) label,
      if (oscTitle.isNotEmpty) oscTitle,
    ].join(' · ');
    recorder.record(
      title: headline,
      message: message,
      variant: variant,
      payload: payload(),
      source: source,
    );
  }

  /// Terminal payloads are arbitrary bytes; drop control characters so a rogue
  /// sequence cannot smuggle newlines or escapes into the notification list.
  static String _sanitize(String value) {
    final out = StringBuffer();
    for (final unit in value.runes) {
      if (unit < 0x20 || unit == 0x7f) {
        out.write(' ');
        continue;
      }
      out.writeCharCode(unit);
    }
    return out.toString().trim();
  }

  static String _clamp(String value) => value.length <= maxBodyChars
      ? value
      : '${value.substring(0, maxBodyChars)}…';
}

class _KittyDraft {
  String title = '';
  String body = '';
  int urgency = 1;
}
