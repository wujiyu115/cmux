import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/workspace_dnd/editor_agent_reference_sender.dart';
import 'package:teampilot/services/workspace_dnd/path_namespace.dart';
import 'package:teampilot/services/workspace_dnd/terminal_text_sink.dart';

/// Captures what the sender stages, standing in for a live PTY.
class _FakeSink implements TerminalTextSink {
  final pasted = <String>[];

  @override
  void appendText(String text) => throw UnimplementedError();

  @override
  Future<void> pasteWithoutSubmit(String text) async => pasted.add(text);
}

void main() {
  group('AgentSelectionReferenceFormatter', () {
    test('multi-line selection renders a start-end range', () {
      expect(
        const AgentSelectionReferenceFormatter()
            .format(relPath: 'lib/src/foo.dart', startLine: 5, endLine: 10),
        '@lib/src/foo.dart#L5-10',
      );
    });

    test('single line collapses to one number', () {
      expect(
        const AgentSelectionReferenceFormatter()
            .format(relPath: 'README.md', startLine: 3, endLine: 3),
        '@README.md#L3',
      );
    });

    test('clipboard format omits the @ sigil', () {
      expect(
        const AgentSelectionReferenceFormatter()
            .formatPathWithLines(relPath: 'lib/a.dart', startLine: 5, endLine: 10),
        'lib/a.dart#L5-10',
      );
      expect(
        const AgentSelectionReferenceFormatter()
            .formatPathWithLines(relPath: 'lib/a.dart', startLine: 7, endLine: 7),
        'lib/a.dart#L7',
      );
    });
  });

  group('EditorAgentClipboardReferenceResolver', () {
    test('resolves a path#L range for a file under a root', () {
      expect(
        const EditorAgentClipboardReferenceResolver().resolve(
          workspaceRoots: const ['/repo'],
          absolutePath: '/repo/lib/a.dart',
          startLine: 2,
          endLine: 2,
        ),
        'lib/a.dart#L2',
      );
    });

    test('returns null outside every root', () {
      expect(
        const EditorAgentClipboardReferenceResolver().resolve(
          workspaceRoots: const ['/repo'],
          absolutePath: '/elsewhere/a.dart',
          startLine: 1,
          endLine: 1,
        ),
        isNull,
      );
    });
  });

  group('EditorAgentReferenceSender', () {
    // PathNamespace.ofCurrentStorage() reports local POSIX when AppStorage is
    // not installed (test default), so these sinks/targets must be local too.
    const localPosixNamespace = PathNamespace.localPosix();

    test('delivers a mention for a file under a workspace root', () async {
      final sink = _FakeSink();
      final outcome = await const EditorAgentReferenceSender().send(
        workspaceRoots: const ['/repo'],
        absolutePath: '/repo/lib/main.dart',
        startLine: 2,
        endLine: 3,
        sink: sink,
        terminalNamespace: localPosixNamespace,
      );

      expect(outcome, AgentReferenceOutcome.delivered);
      expect(sink.pasted.single, '@lib/main.dart#L2-3 ');
    });

    test('longest containing root wins for nested folders', () async {
      final sink = _FakeSink();
      final outcome = await const EditorAgentReferenceSender().send(
        workspaceRoots: const ['/repo', '/repo/packages/shared_ui'],
        absolutePath: '/repo/packages/shared_ui/lib/src/a.dart',
        startLine: 1,
        endLine: 1,
        sink: sink,
        terminalNamespace: localPosixNamespace,
      );

      expect(outcome, AgentReferenceOutcome.delivered);
      // The longest containing root wins: the mention is relative to
      // /repo/packages/shared_ui, not /repo.
      expect(sink.pasted.single, '@lib/src/a.dart#L1 ');
    });

    test('windows-style roots and file paths still produce slash rel paths',
        () async {
      final sink = _FakeSink();
      final outcome = await const EditorAgentReferenceSender().send(
        workspaceRoots: const [r'C:\repo'],
        absolutePath: r'C:\repo\lib\a.dart',
        startLine: 7,
        endLine: 7,
        sink: sink,
        terminalNamespace: localPosixNamespace,
      );

      expect(outcome, AgentReferenceOutcome.delivered);
      expect(sink.pasted.single, '@lib/a.dart#L7 ');
    });

    test('rejects a file outside every workspace root', () async {
      final outcome = await const EditorAgentReferenceSender().send(
        workspaceRoots: const ['/repo'],
        absolutePath: '/elsewhere/a.dart',
        startLine: 1,
        endLine: 1,
        sink: _FakeSink(),
        terminalNamespace: localPosixNamespace,
      );

      expect(outcome, AgentReferenceOutcome.noWorkspaceRoot);
    });

    test('rejects a local file for an SSH terminal', () async {
      final outcome = await const EditorAgentReferenceSender().send(
        workspaceRoots: const ['/repo'],
        absolutePath: '/repo/a.dart',
        startLine: 1,
        endLine: 1,
        sink: _FakeSink(),
        terminalNamespace: const PathNamespace.ssh(),
      );

      expect(outcome, AgentReferenceOutcome.crossNamespace);
    });

    test('reports noSession when no terminal is provided', () async {
      final outcome = await const EditorAgentReferenceSender().send(
        workspaceRoots: const ['/repo'],
        absolutePath: '/repo/a.dart',
        startLine: 1,
        endLine: 1,
        sink: null,
        terminalNamespace: localPosixNamespace,
      );

      expect(outcome, AgentReferenceOutcome.noSession);
    });
  });
}
