import 'package:flutter/services.dart';

/// Inserts recognized speech into a field's value at the caret.
///
/// Replaces the current selection, then collapses the caret after the inserted
/// text so successive final results read as one dictated line.
///
/// A field that has never been focused reports
/// `TextSelection.collapsed(offset: -1)`, and a stale selection can outlive the
/// text it indexed. Both make a naive
/// `text.replaceRange(selection.start, selection.end, text)` throw RangeError —
/// the reference implementation this was ported from does exactly that. Any
/// selection that does not index the current text appends instead.
TextEditingValue insertTranscript(TextEditingValue value, String text) {
  if (text.isEmpty) return value;
  final existing = value.text;
  final selection = value.selection;
  final indexable =
      selection.isValid &&
      selection.start >= 0 &&
      selection.end <= existing.length;
  if (!indexable) {
    final appended = existing + text;
    return TextEditingValue(
      text: appended,
      selection: TextSelection.collapsed(offset: appended.length),
    );
  }
  final updated = existing.replaceRange(selection.start, selection.end, text);
  return TextEditingValue(
    text: updated,
    selection: TextSelection.collapsed(offset: selection.start + text.length),
  );
}
