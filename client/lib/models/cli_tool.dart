/// Backend CLI identity (`flashskyai`, `codex`, `claude`, `opencode`, or
/// `cursor`).
enum CliTool {
  claude('claude'),
  codex('codex'),
  flashskyai('flashskyai'),
  opencode('opencode'),
  cursor('cursor');

  const CliTool(this.value);

  final String value;

  static CliTool decode(Object? raw) => tryParse(raw?.toString()) ?? claude;

  static CliTool? tryParse(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final cli in CliTool.values) {
      if (cli.value == normalized) return cli;
    }
    return null;
  }

  static CliTool parse(Object? raw, {CliTool? fallback}) {
    return tryParse(raw?.toString()) ?? fallback ?? CliTool.claude;
  }
}
