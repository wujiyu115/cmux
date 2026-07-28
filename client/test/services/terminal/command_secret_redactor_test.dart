import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/command_secret_redactor.dart';

void main() {
  group('sanitize', () {
    test('returns null for empty / whitespace-only input', () {
      expect(CommandSecretRedactor.sanitize(null), isNull);
      expect(CommandSecretRedactor.sanitize(''), isNull);
      expect(CommandSecretRedactor.sanitize('   \t '), isNull);
    });

    test('keeps an ordinary command verbatim and trimmed', () {
      expect(
        CommandSecretRedactor.sanitize('  git status --short  '),
        'git status --short',
      );
    });

    test('redacts env-style secret assignments, keeping the name', () {
      expect(
        CommandSecretRedactor.sanitize('MY_API_KEY=hunter2 npm publish'),
        'MY_API_KEY=${CommandSecretRedactor.redacted} npm publish',
      );
      expect(
        CommandSecretRedactor.sanitize('PASSWORD="a b c" ./run.sh'),
        'PASSWORD=${CommandSecretRedactor.redacted} ./run.sh',
      );
      expect(
        CommandSecretRedactor.sanitize("export GH_TOKEN='ghp_abc'"),
        'export GH_TOKEN=${CommandSecretRedactor.redacted}',
      );
    });

    test('leaves non-secret assignments alone', () {
      expect(
        CommandSecretRedactor.sanitize('FOO=bar make build'),
        'FOO=bar make build',
      );
    });

    test('redacts secret flags in both space and equals form', () {
      expect(
        CommandSecretRedactor.sanitize('mysql --password hunter2 -u root'),
        'mysql --password ${CommandSecretRedactor.redacted} -u root',
      );
      expect(
        CommandSecretRedactor.sanitize('curl --api-key=abc123 https://x.test'),
        'curl --api-key=${CommandSecretRedactor.redacted} https://x.test',
      );
      expect(
        CommandSecretRedactor.sanitize('tool -token abc123'),
        'tool -token ${CommandSecretRedactor.redacted}',
      );
    });

    test('redacts credentials embedded in a URI, keeping host and scheme', () {
      expect(
        CommandSecretRedactor.sanitize(
          'git clone https://alice:hunter2@example.test/repo.git',
        ),
        'git clone https://alice:${CommandSecretRedactor.redacted}@example.test/repo.git',
      );
    });

    test('drops a line that is only a typed secret', () {
      expect(CommandSecretRedactor.sanitize('Tr0ub4dor&3'), isNull);
      expect(CommandSecretRedactor.sanitize('my-secret'), isNull);
    });

    test('truncates absurdly long commands', () {
      final long = 'echo ${'a' * 9000}';
      final out = CommandSecretRedactor.sanitize(long);
      expect(out, hasLength(CommandSecretRedactor.maxCommandChars));
    });
  });

  group('looksLikeSecretInput', () {
    test('is false for empty, multi-word, and path-ish values', () {
      expect(CommandSecretRedactor.looksLikeSecretInput(''), isFalse);
      expect(CommandSecretRedactor.looksLikeSecretInput('git status'), isFalse);
      expect(CommandSecretRedactor.looksLikeSecretInput('./build.sh'), isFalse);
      expect(
        CommandSecretRedactor.looksLikeSecretInput(r'C:\tools\run.exe'),
        isFalse,
      );
      expect(
        CommandSecretRedactor.looksLikeSecretInput('/usr/bin/env'),
        isFalse,
      );
    });

    test('is false for well-known bare commands, any case', () {
      for (final command in ['ls', 'flutter', 'kubectl', 'Docker', 'HTOP']) {
        expect(
          CommandSecretRedactor.looksLikeSecretInput(command),
          isFalse,
          reason: command,
        );
      }
    });

    test('is true for a bare token that names a credential', () {
      expect(CommandSecretRedactor.looksLikeSecretInput('mypassword'), isTrue);
      expect(CommandSecretRedactor.looksLikeSecretInput('TOKEN123'), isTrue);
    });

    test('is true for a long opaque mixed-class token', () {
      expect(CommandSecretRedactor.looksLikeSecretInput('abc123def'), isTrue);
      expect(CommandSecretRedactor.looksLikeSecretInput('hunter2!'), isTrue);
    });

    test('is false for short or single-class words', () {
      expect(CommandSecretRedactor.looksLikeSecretInput('a1'), isFalse);
      expect(CommandSecretRedactor.looksLikeSecretInput('runserver'), isFalse);
    });
  });
}
