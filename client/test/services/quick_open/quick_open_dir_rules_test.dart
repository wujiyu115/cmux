import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_index_dirs.dart';
import 'package:teampilot/services/quick_open/quick_open_dir_rules.dart';

void main() {
  group('QuickOpenDirRules.allowsUser (git source)', () {
    test('no user rules allows everything', () {
      const rules = QuickOpenDirRules.none();
      expect(rules.allowsUser('node_modules/pkg/index.js'), isTrue);
      expect(rules.allowsUser('.git/config'), isTrue);
    });

    test('excluded subtree is rejected, deeper include carved back', () {
      final rules = QuickOpenDirRules(
        WorkspaceIndexDirs(
          excluded: ['common'],
          included: ['common/convertor/game_data_server'],
        ),
      );
      expect(rules.allowsUser('common/noise/a.txt'), isFalse);
      expect(
        rules.allowsUser('common/convertor/game_data_server/main.cpp'),
        isTrue,
      );
      expect(rules.allowsUser('common/convertor/other/b.txt'), isFalse);
      expect(rules.allowsUser('README.md'), isTrue);
    });
    test('include carves out the whole subtree, any depth', () {
      final rules = QuickOpenDirRules(
        WorkspaceIndexDirs(
          excluded: ['common'],
          included: ['common/convertor'],
        ),
      );
      expect(rules.allowsUser('common/convertor/a.lua'), isTrue);
      expect(rules.allowsUser('common/convertor/other/a.lua'), isTrue);
      expect(rules.allowsUser('common/convertor/other/sub/a.lua'), isTrue);
      expect(rules.allowsUser('common/other/a.lua'), isFalse);
    });

    test('windows separators are tolerated', () {
      final rules = QuickOpenDirRules(
        WorkspaceIndexDirs(excluded: ['common']),
      );
      expect(rules.allowsUser(r'common\noise\a.txt'), isFalse);
      expect(rules.allowsUser(r'lib\main.dart'), isTrue);
    });
  });

  group('QuickOpenDirRules.allows (recursive source)', () {
    test('built-in ignores apply with no user rules', () {
      const rules = QuickOpenDirRules.none();
      expect(rules.allows('lib/main.dart'), isTrue);
      expect(rules.allows('node_modules/pkg/index.js'), isFalse);
      expect(rules.allows('.idea/workspace.xml'), isFalse);
      expect(rules.allows('lib/.secret.dart'), isFalse);
    });

    test('include overrides the built-in ignores', () {
      final rules = QuickOpenDirRules(
        WorkspaceIndexDirs(included: ['node_modules']),
      );
      expect(rules.allows('node_modules/pkg/index.js'), isTrue);
      expect(rules.allows('lib/main.dart'), isTrue);
    });

    test('deeper exclude wins back over an include', () {
      final rules = QuickOpenDirRules(
        WorkspaceIndexDirs(
          included: ['common'],
          excluded: ['common/vendor'],
        ),
      );
      expect(rules.allows('common/keep/a.dart'), isTrue);
      expect(rules.allows('common/vendor/b.js'), isFalse);
    });

    test('include at the same depth as an exclude loses', () {
      final rules = QuickOpenDirRules(
        WorkspaceIndexDirs(excluded: ['common'], included: ['common']),
      );
      expect(rules.allows('common/a.txt'), isFalse);
    });
  });

  group('isOrphanInclude', () {
    test('flags includes under no exclude', () {
      final rules = QuickOpenDirRules(
        WorkspaceIndexDirs(excluded: ['common'], included: [
          'common/convertor',
          'elsewhere/sub',
        ]),
      );
      expect(rules.isOrphanInclude('common/convertor'), isFalse);
      expect(rules.isOrphanInclude('elsewhere/sub'), isTrue);
    });
  });
}
