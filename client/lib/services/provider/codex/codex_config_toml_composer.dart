import '../../../models/app_provider_config.dart';
import 'codex_agent_status_overlay.dart';
import 'codex_effort_toml.dart';
import 'codex_managed_hook_overlay.dart';
import 'codex_project_trust_toml.dart';
import '../tool_config_generator.dart';

/// Builds the effective `config.toml` body for a Codex session `CODEX_HOME`.
final class CodexConfigTomlComposer {
  const CodexConfigTomlComposer({ToolConfigGenerator? generator})
    : _generator = generator ?? const ToolConfigGenerator();

  final ToolConfigGenerator _generator;

  String compose({
    required AppProviderConfig provider,
    String? hookOverlayToml,
    Iterable<String> trustedProjectDirectories = const [],
    String? reasoningEffortOverride,
  }) {
    var base = _generator.buildCodexConfigToml(provider).trim();
    final effortOverride = reasoningEffortOverride?.trim() ?? '';
    if (effortOverride.isNotEmpty) {
      base = CodexEffortToml.applyReasoningEffort(base, effortOverride);
    }
    final overlay = hookOverlayToml?.trim() ?? '';
    final withOverlay = overlay.isEmpty
        ? base
        : base.isEmpty
        ? overlay
        : (CodexManagedHookOverlay.containsOverlay(base) ||
              CodexAgentStatusOverlay.containsOverlay(base))
        ? base
        : '$base\n\n$overlay';
    return CodexProjectTrustToml.applyTrustedDirectories(
      withOverlay,
      trustedProjectDirectories,
    );
  }
}
