import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor/editor_symbols.dart';

void main() {
  group('extractEditorSymbols', () {
    test('dart: classes, methods, getters skipped, keywords excluded', () {
      const content = '''
import 'dart:async';

abstract class Animal {
  String name;

  void speak() {
    print('hi');
  }

  Future<void> eat() async {
    await Future.delayed(Duration.zero);
  }
}

class Dog extends Animal {
  @override
  void speak() => print('woof');

  bool get isGood => true;
}
''';
      final symbols = extractEditorSymbols('/repo/dog.dart', content);

      final names = symbols.map((s) => s.name).toList();
      expect(names, containsAll(['Animal', 'Dog', 'speak', 'eat']));
      // The block-scoped `if`/control flow must not appear; field/getter
      // lines are not callables either.
      expect(names, isNot(contains('get')));
      expect(names, isNot(contains('isGood')));

      final animal = symbols.firstWhere((s) => s.name == 'Animal');
      expect(animal.kind, EditorSymbolKind.type);
      expect(animal.line, 2);
      final speak = symbols.firstWhere((s) => s.name == 'speak');
      expect(speak.kind, EditorSymbolKind.callable);
      expect(speak.depth, greaterThan(0)); // Indented member of the class.
    });

    test('typescript: class, function, arrow methods', () {
      const content = '''
export interface User {
  id: number;
}

export class UserService {
  async load(id: number): Promise<User> {
    return {} as User;
  }

  format(user: User): string {
    return user.id.toString();
  }
}

function helper(): void {}
''';
      final symbols = extractEditorSymbols('/repo/user.ts', content);

      final names = symbols.map((s) => s.name).toList();
      expect(names, containsAll(['User', 'UserService', 'load', 'format', 'helper']));
    });

    test('python: class and def with async and indentation', () {
      const content = '''
class Runner:
    def run(self):
        pass

    async def stop(self):
        pass
''';
      final symbols = extractEditorSymbols('/repo/runner.py', content);

      final names = symbols.map((s) => s.name).toList();
      expect(names, ['Runner', 'run', 'stop']);
      expect(symbols.first.depth, 0);
      expect(symbols.last.depth, 1);
    });

    test('rust: impl, fn, struct', () {
      const content = '''
struct Point {
    x: i32,
}

impl Point {
    fn new(x: i32) -> Self {
        Point { x }
    }
}
''';
      final symbols = extractEditorSymbols('/repo/point.rs', content);

      final names = symbols.map((s) => s.name).toList();
      expect(names, containsAll(['Point', 'new']));
    });

    test('go: type struct/interface and funcs', () {
      const content = '''
type Server struct {
    Addr string
}

type Handler interface {
    Serve() error
}

func New(addr string) *Server {
    return nil
}
''';
      final symbols = extractEditorSymbols('/repo/server.go', content);

      final types = symbols
          .where((s) => s.kind == EditorSymbolKind.type)
          .map((s) => s.name)
          .toList();
      expect(types, containsAll(['Server', 'Handler']));
      expect(symbols.map((s) => s.name), contains('New'));
    });

    test('markdown: headings with depth', () {
      const content = '''
# Title
Intro text.

## Section A
### Sub
## Section B
''';
      final symbols = extractEditorSymbols('/repo/readme.md', content);

      expect(symbols.map((s) => s.name), [
        'Title',
        'Section A',
        'Sub',
        'Section B',
      ]);
      expect(symbols[2].depth, 2);
    });

    test('json: top-level container keys only', () {
      const content = '''
{
  "name": "app",
  "scripts": {
    "build": "x",
    "deep": {
      "leaf": true
    }
  }
}
''';
      final symbols = extractEditorSymbols('/repo/pkg.json', content);

      // Scalar keys are skipped; only top-level containers are outlined.
      expect(symbols.map((s) => s.name), ['scripts']);
    });

    test('comment lines are skipped', () {
      const content = '''
// class NotReal {
class Real {
''';
      final symbols = extractEditorSymbols('/repo/a.dart', content);
      expect(symbols.map((s) => s.name), ['Real']);
    });

    test('unknown extension yields nothing', () {
      expect(extractEditorSymbols('/repo/a.xyz', 'class A {}'), isEmpty);
      expect(extractEditorSymbols('/repo/a', 'class A {}'), isEmpty);
    });
  });
}
