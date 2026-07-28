import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/command_definition.dart';
import 'package:teampilot/utils/commands/command_palette_filter.dart';

CommandDefinition _cmd(String id) => CommandDefinition(
  id: id,
  category: CommandCategory.view,
  defaultChords: const [],
  when: ShortcutWhen.always,
  terminalPassthrough: true,
  titleL10nKey: id,
);

void main() {
  List<CommandPaletteMatch> run({
    required List<CommandDefinition> catalog,
    required String query,
    required Map<String, String> titles,
    Set<String> unavailable = const {},
    List<String> mru = const [],
    Map<String, String> categories = const {},
  }) {
    return filterCommandPalette(
      catalog: catalog,
      query: query,
      titleOf: (def) => titles[def.id] ?? def.id,
      isAvailable: (def) => !unavailable.contains(def.id),
      mru: mru,
      categoryTitleOf: (def) => categories[def.id] ?? '',
    );
  }

  test('empty query returns all available, MRU-first then catalog order', () {
    final a = _cmd('a');
    final b = _cmd('b');
    final c = _cmd('c');
    final result = run(
      catalog: [a, b, c],
      query: '',
      titles: {'a': 'Alpha', 'b': 'Beta', 'c': 'Gamma'},
      mru: ['c', 'a'],
    );

    expect(result.map((m) => m.command.id), ['c', 'a', 'b']);
    expect(result.every((m) => m.score == 0), isTrue);
    expect(result.every((m) => m.matchedIndexes.isEmpty), isTrue);
  });

  test('subsequence match keeps only commands whose title contains the query',
      () {
    final a = _cmd('a');
    final b = _cmd('b');
    final result = run(
      catalog: [a, b],
      query: 'spl',
      titles: {'a': 'Split Terminal', 'b': 'Toggle Sidebar'},
    );

    expect(result.map((m) => m.command.id), ['a']);
  });

  test('contiguous run beats a scattered subsequence', () {
    final contiguous = _cmd('contig');
    final scattered = _cmd('scatter');
    final result = run(
      catalog: [scattered, contiguous],
      query: 'ab',
      // Same length, same first-match index, no word-start matches: contiguity
      // in the first is the only difference.
      titles: {'contig': 'xabx', 'scatter': 'xaxb'},
    );

    expect(result.first.command.id, 'contig');
  });

  test('word-start match beats a mid-word match', () {
    final start = _cmd('start');
    final mid = _cmd('mid');
    final result = run(
      catalog: [mid, start],
      query: 't',
      // 't' at a word start vs. 't' mid-word.
      titles: {'start': 'Run Test', 'mid': 'Bottle'},
    );

    expect(result.first.command.id, 'start');
  });

  test('unavailable commands are excluded', () {
    final a = _cmd('a');
    final b = _cmd('b');
    final result = run(
      catalog: [a, b],
      query: 'a',
      titles: {'a': 'Alpha', 'b': 'Ash'},
      unavailable: {'a'},
    );

    expect(result.map((m) => m.command.id), ['b']);
  });

  test('matched indexes point at the matched title characters', () {
    final a = _cmd('a');
    final result = run(
      catalog: [a],
      query: 'st',
      titles: {'a': 'Split'},
    );

    final match = result.single;
    expect(match.matchedIndexes, [0, 4]); // 'S' at 0, 't' at 4
    for (final index in match.matchedIndexes) {
      expect(match.title[index].toLowerCase(), isNotEmpty);
    }
    expect(match.title[0].toLowerCase(), 's');
    expect(match.title[4].toLowerCase(), 't');
  });

  test('equal scores fall back to MRU then catalog order deterministically',
      () {
    final a = _cmd('a');
    final b = _cmd('b');
    final c = _cmd('c');
    // Identical titles → identical scores for query 'x'.
    final titles = {'a': 'X', 'b': 'X', 'c': 'X'};

    final withMru = run(
      catalog: [a, b, c],
      query: 'x',
      titles: titles,
      mru: ['c'],
    );
    // 'c' floats up via MRU; 'a','b' keep catalog order.
    expect(withMru.map((m) => m.command.id), ['c', 'a', 'b']);

    final noMru = run(catalog: [a, b, c], query: 'x', titles: titles);
    expect(noMru.map((m) => m.command.id), ['a', 'b', 'c']);
  });

  test('non-matching title still matches via category fallback (no highlight)',
      () {
    final a = _cmd('a');
    final result = run(
      catalog: [a],
      query: 'term',
      titles: {'a': 'Split Right'},
      categories: {'a': 'Terminal'},
    );

    final match = result.single;
    expect(match.command.id, 'a');
    expect(match.matchedIndexes, isEmpty);
  });

  test('no subsequence match excludes the command', () {
    final a = _cmd('a');
    final result = run(
      catalog: [a],
      query: 'zzz',
      titles: {'a': 'Split'},
    );

    expect(result, isEmpty);
  });
}
