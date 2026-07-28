import 'osc_sequence_scanner.dart';

/// OSC title extraction from raw PTY output (cmds 0/1/2).
///
/// Thin façade over [OscSequenceScanner] — the parsing (BEL/ST terminators,
/// chunk-split pending tail, payload cap) lives there so title and shell
/// integration share one implementation.
class OscTitleExtractor {
  OscTitleExtractor()
    : _scanner = OscSequenceScanner(
        codes: _titleCommands,
        maxPayloadChars: maxOscTitleChars,
      );

  static const int maxOscTitleChars = 1024;

  static const Set<int> _titleCommands = {0, 1, 2};

  final OscSequenceScanner _scanner;

  /// Feed a PTY text chunk; returns newly completed titles in order.
  List<String> push(String data) {
    final found = _scanner.push(data);
    if (found.isEmpty) return const [];
    return [for (final sequence in found) sequence.payload];
  }

  void reset() => _scanner.reset();

  /// Last complete OSC title in [data], or null.
  static String? extractLast(String data) {
    final found = extractAll(data);
    return found.isEmpty ? null : found.last;
  }

  /// All complete OSC titles in [data] (cmds 0/1/2).
  static List<String> extractAll(String data) {
    final found = OscSequenceScanner.extractAll(
      data,
      codes: _titleCommands,
      maxPayloadChars: maxOscTitleChars,
    );
    if (found.isEmpty) return const [];
    return [for (final sequence in found) sequence.payload];
  }
}
