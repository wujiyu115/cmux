/// Generic OSC sequence scanning over raw PTY text.
///
/// The engine already surfaces OSC 0/1/2 (title), 7 (cwd) and 9/777
/// (notifications). This scanner exists for the codes it does *not* handle —
/// OSC 99 (kitty notifications) and OSC 133 (shell integration) — and backs
/// [OscTitleExtractor] so there is one parser, not two.
///
/// Algorithm ported from Orca `osc-title-extraction.ts`: BEL or ST terminator,
/// a pending tail so sequences split across PTY chunks still resolve, and a
/// bounded payload so a runaway sequence cannot grow memory.
class OscSequenceScanner {
  OscSequenceScanner({Set<int>? codes, this.maxPayloadChars = maxOscPayloadChars})
    : codes = codes == null ? null : Set.unmodifiable(codes);

  /// Codes to report; null reports every well-formed sequence.
  final Set<int>? codes;

  /// Payload length cap. Longer payloads are middle-elided, never dropped.
  final int maxPayloadChars;

  static const int maxOscPayloadChars = 1024;
  static const int _scanTailLimit = 4096;

  /// Longest prefix kept when eliding an over-long pending tail: `ESC ] 1 3 3 ;`
  /// still identifies the sequence.
  static const int _oscPrefixLength = 8;

  /// Most digits accepted for a code (`777` / `1337` style).
  static const int _maxCodeDigits = 4;

  static const int _esc = 0x1b;
  static const int _bel = 0x07;
  static const int _rightBracket = 0x5d;
  static const int _backslash = 0x5c;
  static const int _semicolon = 0x3b;
  static const int _zero = 0x30;
  static const int _nine = 0x39;

  String _pending = '';

  /// Feed a PTY text chunk; returns the sequences completed by it, in order.
  List<OscSequence> push(String data) {
    if (data.isEmpty && _pending.isEmpty) return const [];
    final input = '$_pending$data';
    final found = extractAll(
      input,
      codes: codes,
      maxPayloadChars: maxPayloadChars,
    );
    _pending = scanTail(input);
    return found;
  }

  void reset() => _pending = '';

  /// All complete OSC sequences in [data], optionally filtered to [codes].
  static List<OscSequence> extractAll(
    String data, {
    Set<int>? codes,
    int maxPayloadChars = maxOscPayloadChars,
  }) {
    if (!data.contains('\x1b]')) return const [];
    final out = <OscSequence>[];
    var searchStart = 0;
    while (searchStart < data.length) {
      final start = data.indexOf('\x1b]', searchStart);
      if (start == -1) break;
      final parsed = _parseAt(data, start, maxPayloadChars);
      switch (parsed) {
        case _OscFound(:final sequence, :final nextIndex):
          if (codes == null || codes.contains(sequence.code)) {
            out.add(sequence);
          }
          searchStart = nextIndex;
        case _OscInvalid(:final nextIndex):
          searchStart = nextIndex;
        case _OscIncomplete():
          return out;
      }
    }
    return out;
  }

  /// Unterminated trailing sequence to prepend to the next chunk, if any.
  static String scanTail(String input) {
    final lastOsc = input.lastIndexOf('\x1b]');
    if (lastOsc != -1) {
      final suffix = input.substring(lastOsc);
      if (!suffix.contains('\x07') && !suffix.contains('\x1b\\')) {
        return _trimScanTail(suffix);
      }
      return input.endsWith('\x1b') ? '\x1b' : '';
    }
    return input.endsWith('\x1b') ? '\x1b' : '';
  }

  static String _trimScanTail(String value) {
    if (value.length <= _scanTailLimit) return value;
    final prefixLen = value.length < _oscPrefixLength
        ? value.length
        : _oscPrefixLength;
    final prefix = value.substring(0, prefixLen);
    final suffixBudget = _scanTailLimit - prefix.length;
    if (suffixBudget <= 0) return prefix;
    return '$prefix${value.substring(value.length - suffixBudget)}';
  }

  static _OscParseResult _parseAt(String data, int index, int maxPayloadChars) {
    if (!_isIntroducerAt(data, index)) {
      return _OscInvalid(index + 1);
    }
    var cursor = index + 2;
    var code = 0;
    var digits = 0;
    while (cursor < data.length && _isDigit(data.codeUnitAt(cursor))) {
      if (digits == _maxCodeDigits) return _OscInvalid(index + 2);
      code = code * 10 + (data.codeUnitAt(cursor) - _zero);
      digits++;
      cursor++;
    }
    if (cursor >= data.length) return const _OscIncomplete();
    if (digits == 0) return _OscInvalid(index + 2);

    // `ESC ] 133 ; A` — the separator is optional so bare `ESC ] 9 BEL` and
    // similar payload-less sequences still parse.
    if (data.codeUnitAt(cursor) == _semicolon) cursor++;
    final payloadStart = cursor;

    for (; cursor < data.length; cursor++) {
      final unit = data.codeUnitAt(cursor);
      if (unit == _bel) {
        return _OscFound(
          sequence: OscSequence(
            code: code,
            payload: _boundedPayload(
              data,
              payloadStart,
              cursor,
              maxPayloadChars,
            ),
          ),
          nextIndex: cursor + 1,
        );
      }
      if (unit != _esc) continue;
      if (cursor + 1 >= data.length) return const _OscIncomplete();
      if (data.codeUnitAt(cursor + 1) == _backslash) {
        return _OscFound(
          sequence: OscSequence(
            code: code,
            payload: _boundedPayload(
              data,
              payloadStart,
              cursor,
              maxPayloadChars,
            ),
          ),
          nextIndex: cursor + 2,
        );
      }
      // A fresh ESC inside the payload aborts this sequence; rescan from it so
      // the following (valid) sequence is not swallowed.
      return _OscInvalid(cursor);
    }
    return const _OscIncomplete();
  }

  static bool _isDigit(int unit) => unit >= _zero && unit <= _nine;

  static bool _isIntroducerAt(String data, int index) =>
      index + 1 < data.length &&
      data.codeUnitAt(index) == _esc &&
      data.codeUnitAt(index + 1) == _rightBracket;

  /// Keeps head and tail so both the sequence's parameters and its end survive.
  static String _boundedPayload(
    String data,
    int start,
    int end,
    int maxPayloadChars,
  ) {
    final length = end - start;
    if (length <= maxPayloadChars) return data.substring(start, end);
    final prefixLength = (maxPayloadChars / 2).ceil();
    final suffixLength = maxPayloadChars - prefixLength;
    return data.substring(start, start + prefixLength) +
        data.substring(end - suffixLength, end);
  }
}

/// One complete OSC sequence: its numeric code and everything after the first
/// `;` separator (empty when the sequence carried no payload).
class OscSequence {
  const OscSequence({required this.code, required this.payload});

  final int code;
  final String payload;

  @override
  bool operator ==(Object other) =>
      other is OscSequence && other.code == code && other.payload == payload;

  @override
  int get hashCode => Object.hash(code, payload);

  @override
  String toString() => 'OscSequence($code, ${payload.length} chars)';
}

sealed class _OscParseResult {
  const _OscParseResult();
}

final class _OscFound extends _OscParseResult {
  const _OscFound({required this.sequence, required this.nextIndex});
  final OscSequence sequence;
  final int nextIndex;
}

final class _OscInvalid extends _OscParseResult {
  const _OscInvalid(this.nextIndex);
  final int nextIndex;
}

final class _OscIncomplete extends _OscParseResult {
  const _OscIncomplete();
}
