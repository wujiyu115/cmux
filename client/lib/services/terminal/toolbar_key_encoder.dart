/// Applies the toolbar's one-shot Ctrl / Alt modifiers to a key's bytes.
///
/// Single bytes follow the terminal conventions every shell expects: Ctrl masks
/// to the control range, Alt sends an ESC prefix (8-bit meta is never used).
/// Multi-byte escape sequences instead get the xterm *modifier parameter* — 5
/// for Ctrl, 3 for Alt — because `ESC` + `CSI A` is not "Ctrl+Up" to anything.
///
/// [ctrl] takes precedence if both are set; the cubit keeps them mutually
/// exclusive, so that only guards against a caller mistake.
///
/// The result must not be mutated: pass-through returns the caller's own list,
/// which may be an unmodifiable `String.codeUnits` view or an entry of the
/// shared global key table.
List<int> encodeToolbarKey(
  List<int> bytes, {
  bool ctrl = false,
  bool alt = false,
}) {
  if (bytes.isEmpty) return const [];
  if (ctrl) {
    if (bytes.length == 1) {
      final code = bytes.first;
      // `/` and `?` are the two toolbar keys whose Ctrl form xterm defines
      // outside the maskable band, so they need explicit mappings. The rest of
      // the toolbar punctuation (- = : ; ! * $ % < > parens) has no standard
      // Ctrl form and is deliberately left alone rather than invented.
      if (code == 0x2f) return const [0x1f];
      if (code == 0x3f) return const [0x7f];
      // Masking only makes sense inside 0x40..0x7f — that band includes DEL,
      // so Ctrl+DEL becomes 0x1f. Anything below it (Tab, Esc, …) is already a
      // control code and passes through untouched.
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
  if (bytes.length == 3) {
    // Only rewrite when the third byte really terminates the sequence,
    // otherwise `CSI 5` would come out as the nonsense `CSI 1;<m> 5`.
    final isFinal = bytes[2] >= 0x40 && bytes[2] <= 0x7e;
    return isFinal ? [...csi, 0x31, 0x3b, ...m, bytes[2]] : bytes;
  }
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
