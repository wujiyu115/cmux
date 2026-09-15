import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_index_dirs.dart';

void main() {
  group('normalizeIndexDirRule', () {
    test('trims, unifies separators, strips ./ and trailing /', () {
      expect(normalizeIndexDirRule(' common/convertor '), 'common/convertor');
      expect(normalizeIndexDirRule(r'.\common\convertor'), 'common/convertor');
      expect(normalizeIndexDirRule('common//'), 'common');
      expect(normalizeIndexDirRule('./a/b/'), 'a/b');
    });

    test('rejects absolute paths, empties and separator-only input', () {
      expect(normalizeIndexDirRule('/abs/path'), '');
      expect(normalizeIndexDirRule(r'\abs\path'), '');
      expect(normalizeIndexDirRule(''), '');
      expect(normalizeIndexDirRule('   '), '');
      expect(normalizeIndexDirRule('/'), '');
      expect(normalizeIndexDirRule('.'), '');
    });
  });

  group('WorkspaceIndexDirs', () {
    test('normalizes, dedupes and drops empties on construction', () {
      final dirs = WorkspaceIndexDirs(
        excluded: ['common', 'common/', ' lib ', '', r'logs\'],
        included: ['a/b'],
      );
      expect(dirs.excluded, ['common', 'lib', 'logs']);
      expect(dirs.included, ['a/b']);
    });

    test('fromJson tolerates junk and defaults empty', () {
      expect(WorkspaceIndexDirs.fromJson(null).isEmpty, isTrue);
      expect(WorkspaceIndexDirs.fromJson('x').isEmpty, isTrue);
      final dirs = WorkspaceIndexDirs.fromJson({
        'excluded': ['common', 5, null],
        'included': 'nope',
      });
      expect(dirs.excluded, ['common']);
      expect(dirs.included, isEmpty);
    });

    test('toJson omits empty lists and round-trips via fromJson', () {
      expect(WorkspaceIndexDirs.empty().toJson(), isEmpty);
      final dirs = WorkspaceIndexDirs(
        excluded: ['common'],
        included: ['common/convertor'],
      );
      final round = WorkspaceIndexDirs.fromJson(dirs.toJson());
      expect(round, dirs);
      expect(round.isEmpty, isFalse);
    });

    test('value equality follows the normalized lists', () {
      expect(
        WorkspaceIndexDirs(excluded: ['common']),
        WorkspaceIndexDirs(excluded: ['common/']),
      );
      expect(
        WorkspaceIndexDirs(excluded: ['a']).hashCode,
        WorkspaceIndexDirs(excluded: ['a']).hashCode,
      );
      expect(
        WorkspaceIndexDirs(excluded: ['a']),
        isNot(WorkspaceIndexDirs(excluded: ['b'])),
      );
    });
  });
}
