import '../../utils/workspace/workspace_path_utils.dart';
import 'path_namespace.dart';
import 'terminal_text_sink.dart';

/// Renders a selected editor line range as an agent-CLI reference.
///
/// The reference grammar is the `@path#L<start>-<end>` shape Claude Code's
/// VS Code / JetBrains extensions insert (single line collapses to `#L<start>`).
/// Agent CLIs parse the mention out of the prompt themselves; we never read
/// the file content — a workspace-relative path plus the line range is enough.
class AgentSelectionReferenceFormatter {
  const AgentSelectionReferenceFormatter();

  /// [relPath] is already workspace-relative with `/` separators;
  /// [startLine]/[endLine] are 1-based, inclusive, start <= end.
  String format({
    required String relPath,
    required int startLine,
    required int endLine,
  }) {
    final range = startLine == endLine ? '$startLine' : '$startLine-$endLine';
    return '@$relPath#L$range';
  }

  /// Same range grammar without the `@` sigil, for clipboard copies the
  /// user pastes anywhere (chat, issue trackers, other tools).
  String formatPathWithLines({
    required String relPath,
    required int startLine,
    required int endLine,
  }) {
    final range = startLine == endLine ? '$startLine' : '$startLine-$endLine';
    return '$relPath#L$range';
  }
}

/// Outcome of one send-agent-reference attempt.
enum AgentReferenceOutcome {
  /// The reference was staged into the active terminal's input line.
  delivered,

  /// The editor file lies outside every workspace folder, so no
  /// workspace-relative mention could be formed.
  noWorkspaceRoot,

  /// The file's machine differs from the active terminal's (local file onto
  /// an SSH terminal, etc.), so the CLI there cannot resolve the path.
  crossNamespace,

  /// No session terminal exists in this workspace yet.
  noSession,
}

/// Resolves the selected line range to a `path#L<start>-<end>` clipboard
/// string — the send grammar minus the `@` sigil and minus any terminal.
///
/// Returns null when the file lies outside every workspace folder (no
/// workspace-relative reference can be formed).
class EditorAgentClipboardReferenceResolver {
  const EditorAgentClipboardReferenceResolver({
    this.formatter = const AgentSelectionReferenceFormatter(),
  });

  final AgentSelectionReferenceFormatter formatter;

  String? resolve({
    required List<String> workspaceRoots,
    required String absolutePath,
    required int startLine,
    required int endLine,
  }) {
    final rel = relativePathWithinRoots(workspaceRoots, absolutePath);
    if (rel == null) return null;
    return formatter.formatPathWithLines(
      relPath: rel,
      startLine: startLine,
      endLine: endLine,
    );
  }
}

/// Sends the editor's selected line range to the workspace's active session
/// terminal as an agent mention, then flips the workbench tab to that
/// terminal so the user sees the staged reference land.
///
/// Pure projection + delivery (same shape as `TerminalDropIngestor`): no
/// cubits, no PTYs — the injected [TerminalTextSink] keeps this unit-testable.
///
/// The mention is workspace-relative, so path *style* (Windows ⇄ POSIX) never
/// matters; only the *machine* has to match the terminal's.
class EditorAgentReferenceSender {
  const EditorAgentReferenceSender({
    this.formatter = const AgentSelectionReferenceFormatter(),
  });

  final AgentSelectionReferenceFormatter formatter;

  Future<AgentReferenceOutcome> send({
    required List<String> workspaceRoots,
    required String absolutePath,
    required int startLine,
    required int endLine,
    required TerminalTextSink? sink,
    required PathNamespace terminalNamespace,
  }) async {
    if (sink == null) return AgentReferenceOutcome.noSession;

    final rel = relativePathWithinRoots(workspaceRoots, absolutePath);
    if (rel == null) return AgentReferenceOutcome.noWorkspaceRoot;

    final sourceNamespace = PathNamespace.ofCurrentStorage();
    if (!sourceNamespace.sameHostAs(terminalNamespace)) {
      return AgentReferenceOutcome.crossNamespace;
    }

    // Mentions are prompt tokens the agent CLI reads as text, not shell
    // words, so no quoting. Trailing space leaves the cursor ready for the
    // user's question — same delivery shape as a dragged path.
    final mention = formatter.format(
      relPath: rel,
      startLine: startLine,
      endLine: endLine,
    );
    await sink.pasteWithoutSubmit('$mention ');
    return AgentReferenceOutcome.delivered;
  }
}
