import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'pending_user_message.dart';
import 'terminal_color_scheme_report.dart';
import '../../utils/terminal/every_user_line_capture.dart';
import '../../utils/terminal/first_user_line_capture.dart';

/// Engine→PTY byte path: user-line capture + OSC 997 stripping.
///
/// SRP: isolates input-side effects from session lifecycle and display I/O.
final class TerminalUserInputPipeline {
  TerminalUserInputPipeline({
    StreamController<PendingUserMessage>? parkedSubmissions,
  }) : _parkedSubmissions =
           parkedSubmissions ??
           StreamController<PendingUserMessage>.broadcast();

  final StreamController<PendingUserMessage> _parkedSubmissions;

  Stream<PendingUserMessage> get parkedUserSubmissions =>
      _parkedSubmissions.stream;

  FirstUserLineCapture? _firstUserLineCapture;
  EveryUserLineCapture? _everyUserLineCapture;
  EveryUserLineCapture? _turnStartCapture;
  var _forwardsColorScheme = true;

  void install({
    void Function(String line)? onFirstUserLineSubmitted,
    void Function(String line)? onEveryUserLineSubmitted,
    void Function()? onTurnStart,
    bool forwardsColorScheme = true,
  }) {
    _forwardsColorScheme = forwardsColorScheme;
    _firstUserLineCapture = onFirstUserLineSubmitted == null
        ? null
        : FirstUserLineCapture(onFirstUserLineSubmitted);
    _everyUserLineCapture = onEveryUserLineSubmitted == null
        ? null
        : EveryUserLineCapture(onEveryUserLineSubmitted);
    _turnStartCapture = onTurnStart == null
        ? null
        : EveryUserLineCapture((_) => onTurnStart());
  }

  void installWorkspaceShell() {
    _forwardsColorScheme = true;
    _firstUserLineCapture = null;
    _everyUserLineCapture = null;
    _turnStartCapture = null;
  }

  void clear() {
    _firstUserLineCapture = null;
    _everyUserLineCapture = null;
    _turnStartCapture = null;
  }

  bool isUnreadParkedMessage(String id) => false;

  /// Transform engine output before forwarding to the PTY (capture + filter).
  Uint8List transformEngineToPty(Uint8List data) {
    if (_firstUserLineCapture != null ||
        _everyUserLineCapture != null ||
        _turnStartCapture != null) {
      final decoded = utf8.decode(data, allowMalformed: true);
      _firstUserLineCapture?.feed(decoded);
      _everyUserLineCapture?.feed(decoded);
      _turnStartCapture?.feed(decoded);
    }
    var forward = data;
    if (!_forwardsColorScheme) {
      forward = stripColorSchemeReport(forward);
    }
    return forward;
  }

  Future<void> close() => _parkedSubmissions.close();
}
