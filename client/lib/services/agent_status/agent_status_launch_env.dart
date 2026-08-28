import 'dart:io';

import 'agent_hook_installer.dart';
import 'member_agent_status_endpoint.dart';

/// Builds the per-pane launch env that the shared agent hook reads at run time.
///
/// The hook script no-ops unless all three keys are present, so this is the
/// single seam that decides whether a pane reports agent status at all. Both
/// launch paths use it: session tabs (`SessionShellConnector`) and workspace
/// terminals (`WorkspaceShellConnector`).
abstract final class AgentStatusLaunchEnv {
  /// The keys that must survive the jump into a WSL distro.
  static const forwardedKeys = <String>[
    agentStatusUrlEnvKey,
    agentStatusSessionEnvKey,
    agentStatusMemberEnvKey,
  ];

  /// Seat identity env for a pane dialing [endpoint].
  ///
  /// [seatId] is used for BOTH the session and member keys. Seats are keyed by
  /// session id and member id joined by a NUL (see `AgentStatusSeatLookup`), so
  /// keeping the two equal is what makes the gateway lookup match the
  /// `registerSeat` call made at connect.
  ///
  /// When [usesWsl] is true a `WSLENV` declaration is added — `wsl.exe` drops
  /// every Windows variable that is not listed there, so without it the three
  /// keys never reach the distro and the hook silently no-ops.
  static Map<String, String> build({
    required String endpoint,
    required String seatId,
    required bool usesWsl,
    Map<String, String>? hostEnvironment,
  }) {
    final env = <String, String>{
      agentStatusUrlEnvKey: endpoint,
      agentStatusSessionEnvKey: seatId,
      agentStatusMemberEnvKey: seatId,
    };
    if (usesWsl) {
      final declaration = buildWslEnvDeclaration(
        hostEnvironment: hostEnvironment,
      );
      if (declaration.isNotEmpty) env['WSLENV'] = declaration;
    }
    return env;
  }

  /// `WSLENV` value that forwards [forwardedKeys] while preserving whatever the
  /// host already declared.
  ///
  /// Must merge rather than replace: the returned map is spread AFTER
  /// `Platform.environment` in `PtyLaunchEnvironment.buildPtyEnvironment`, so a
  /// bare assignment would silently drop the user's own `WSLENV` entries.
  ///
  /// Entries may carry translation flags (`VAR/p`, `VAR/l`, `VAR/u`, `VAR/w`);
  /// dedup compares the name before the slash and keeps the host's flags. Our
  /// own keys are declared flagless — a URL and two opaque ids must not be
  /// path-translated.
  static String buildWslEnvDeclaration({
    Map<String, String>? hostEnvironment,
  }) {
    final existing = (hostEnvironment ?? Platform.environment)['WSLENV'] ?? '';
    final entries = <String>[];
    final seen = <String>{};

    void add(String raw) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return;
      final name = trimmed.split('/').first;
      if (name.isEmpty) return;
      if (!seen.add(name)) return;
      entries.add(trimmed);
    }

    for (final entry in existing.split(':')) {
      add(entry);
    }
    for (final key in forwardedKeys) {
      add(key);
    }
    return entries.join(':');
  }
}
