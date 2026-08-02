import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/stt/transcript_insertion.dart';

void main() {
  test('appends when the field has never been focused', () {
    // A TextField that never took focus reports offset -1. Nexterm's port of
    // this calls text.replaceRange(-1, -1, …) here and throws RangeError.
    const value = TextEditingValue(
      text: 'ls',
      selection: TextSelection.collapsed(offset: -1),
    );
    final result = insertTranscript(value, ' -la');
    expect(result.text, 'ls -la');
    expect(result.selection, const TextSelection.collapsed(offset: 6));
  });

  test('inserts at a collapsed caret', () {
    const value = TextEditingValue(
      text: 'ls -la',
      selection: TextSelection.collapsed(offset: 2),
    );
    final result = insertTranscript(value, ' -h');
    expect(result.text, 'ls -h -la');
    expect(result.selection, const TextSelection.collapsed(offset: 5));
  });

  test('replaces the selection', () {
    const value = TextEditingValue(
      text: 'git commit',
      selection: TextSelection(baseOffset: 4, extentOffset: 10),
    );
    final result = insertTranscript(value, 'push');
    expect(result.text, 'git push');
    expect(result.selection, const TextSelection.collapsed(offset: 8));
  });

  test('replaces a reversed selection', () {
    // Dragging right-to-left leaves base > extent; start/end must be used, not
    // base/extent.
    const value = TextEditingValue(
      text: 'git commit',
      selection: TextSelection(baseOffset: 10, extentOffset: 4),
    );
    final result = insertTranscript(value, 'push');
    expect(result.text, 'git push');
    expect(result.selection, const TextSelection.collapsed(offset: 8));
  });

  test('returns the value unchanged for empty text', () {
    const value = TextEditingValue(
      text: 'ls',
      selection: TextSelection.collapsed(offset: 1),
    );
    expect(insertTranscript(value, ''), value);
  });

  test('appends when the selection points past the end of the text', () {
    // A stale selection left over from a longer draft must not throw.
    const value = TextEditingValue(
      text: 'ls',
      selection: TextSelection.collapsed(offset: 99),
    );
    final result = insertTranscript(value, ' -la');
    expect(result.text, 'ls -la');
    expect(result.selection, const TextSelection.collapsed(offset: 6));
  });

  test('accumulates across successive inserts', () {
    // Each final result from the recognizer is a separate insert; they have to
    // read as one dictated line.
    var value = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
    );
    for (final chunk in ['git ', 'commit ', '-m hello']) {
      value = insertTranscript(value, chunk);
    }
    expect(value.text, 'git commit -m hello');
    expect(value.selection, const TextSelection.collapsed(offset: 19));
  });
}
