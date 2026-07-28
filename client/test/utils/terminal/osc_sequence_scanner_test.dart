import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/terminal/osc_sequence_scanner.dart';
import 'package:teampilot/utils/terminal/osc_title_extractor.dart';

const _esc = '\x1b';
const _bel = '\x07';
const _st = '$_esc\\';

void main() {
  group('extractAll', () {
    test('parses code and payload for BEL and ST terminators', () {
      expect(OscSequenceScanner.extractAll('$_esc]0;hello$_bel'), const [
        OscSequence(code: 0, payload: 'hello'),
      ]);
      expect(OscSequenceScanner.extractAll('$_esc]133;D;0$_st'), const [
        OscSequence(code: 133, payload: 'D;0'),
      ]);
    });

    test('reads multi-digit codes and payload-less sequences', () {
      expect(OscSequenceScanner.extractAll('$_esc]777;notify;a;b$_bel'), const [
        OscSequence(code: 777, payload: 'notify;a;b'),
      ]);
      expect(OscSequenceScanner.extractAll('$_esc]133$_bel'), const [
        OscSequence(code: 133, payload: ''),
      ]);
    });

    test('filters to the requested codes', () {
      const data = '$_esc]2;title$_bel$_esc]99;i=1;body$_bel';
      expect(OscSequenceScanner.extractAll(data, codes: const {99}), const [
        OscSequence(code: 99, payload: 'i=1;body'),
      ]);
      expect(OscSequenceScanner.extractAll(data).length, 2);
    });

    test('an aborted sequence does not swallow the next one', () {
      final found = OscSequenceScanner.extractAll(
        '$_esc]0;broken$_esc[0m$_esc]0;good$_bel',
      );
      expect(found, const [OscSequence(code: 0, payload: 'good')]);
    });

    test('ignores malformed introducers without a numeric code', () {
      expect(OscSequenceScanner.extractAll('$_esc];nope$_bel'), isEmpty);
      expect(OscSequenceScanner.extractAll('$_esc]12345;x$_bel'), isEmpty);
      expect(OscSequenceScanner.extractAll('no escapes here'), isEmpty);
    });

    test('unterminated sequences are not reported', () {
      expect(OscSequenceScanner.extractAll('$_esc]9;pending'), isEmpty);
    });

    test('over-long payloads are middle-elided, not dropped', () {
      final payload = '${'a' * 40}TAIL';
      final found = OscSequenceScanner.extractAll(
        '$_esc]9;$payload$_bel',
        maxPayloadChars: 10,
      );
      expect(found.single.code, 9);
      expect(found.single.payload.length, 10);
      expect(found.single.payload.startsWith('aaaaa'), isTrue);
      expect(found.single.payload.endsWith('TAIL'), isTrue);
    });
  });

  group('push', () {
    test('resolves a sequence split across chunks', () {
      final scanner = OscSequenceScanner(codes: const {133});
      expect(scanner.push('$_esc]13'), isEmpty);
      expect(scanner.push('3;C'), isEmpty);
      expect(scanner.push(';cmd$_bel'), const [
        OscSequence(code: 133, payload: 'C;cmd'),
      ]);
    });

    test('reports each sequence exactly once across chunks', () {
      final scanner = OscSequenceScanner();
      expect(scanner.push('$_esc]9;one$_bel$_esc]9;tw'), const [
        OscSequence(code: 9, payload: 'one'),
      ]);
      expect(scanner.push('o$_bel'), const [
        OscSequence(code: 9, payload: 'two'),
      ]);
    });

    test('a lone trailing ESC is buffered, not lost', () {
      final scanner = OscSequenceScanner();
      expect(scanner.push('text$_esc'), isEmpty);
      expect(scanner.push(']9;hi$_bel'), const [
        OscSequence(code: 9, payload: 'hi'),
      ]);
    });

    test('reset drops the pending tail', () {
      final scanner = OscSequenceScanner();
      scanner.push('$_esc]9;half');
      scanner.reset();
      expect(scanner.push('rest$_bel'), isEmpty);
    });

    test('a runaway pending tail stays bounded', () {
      final scanner = OscSequenceScanner();
      expect(scanner.push('$_esc]133;${'x' * 20000}'), isEmpty);
      // The tail was elided but the sequence still terminates, and the chunk
      // after it parses normally.
      final found = scanner.push('$_bel$_esc]9;ok$_bel');
      expect(found.length, 2);
      expect(found.first.code, 133);
      expect(found.first.payload.length, OscSequenceScanner.maxOscPayloadChars);
      expect(found.last, const OscSequence(code: 9, payload: 'ok'));
    });
  });

  group('OscTitleExtractor stays a thin façade', () {
    test('titles come from codes 0/1/2 only', () {
      const data =
          '$_esc]0;zero$_bel$_esc]1;one$_bel'
          '$_esc]2;two$_bel$_esc]9;notify$_bel';
      expect(OscTitleExtractor.extractAll(data), ['zero', 'one', 'two']);
      expect(OscTitleExtractor.extractLast(data), 'two');
    });

    test('shares the chunk-split behaviour', () {
      final extractor = OscTitleExtractor();
      expect(extractor.push('$_esc]2;par'), isEmpty);
      expect(extractor.push('tial$_bel'), ['partial']);
    });
  });
}
