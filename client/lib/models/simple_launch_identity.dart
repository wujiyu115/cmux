import 'package:flutter/foundation.dart';

import 'cli_tool.dart';

/// Denormalized Simple (unteamed) launch identity.
///
/// Persisted on [AppSession]. Create resolves once; reconnect reuses the
/// stored provider/model/cli.
@immutable
class SimpleLaunchIdentity {
  const SimpleLaunchIdentity({
    required this.cli,
    this.provider = '',
    this.model = '',
    this.effort = '',
    this.presetId = '',
  });

  final CliTool cli;
  final String provider;
  final String model;
  final String effort;

  /// Provenance only — which global preset was chosen at create.
  final String presetId;

  /// Preferred official catalog id when provider is unset.
  static String? officialProviderIdFor(CliTool cli) => switch (cli) {
    CliTool.claude => 'claude-official',
    CliTool.cursor => 'cursor-account',
    CliTool.codex => 'openai-official',
    CliTool.opencode => 'opencode',
    CliTool.flashskyai => null,
  };

  /// Create-time resolve: empty provider → official catalog id for [cli].
  factory SimpleLaunchIdentity.resolve({
    CliTool? cli,
    String? provider,
    String? model,
    String? effort,
    String? presetId,
  }) {
    final resolvedCli = cli ?? CliTool.claude;
    var resolvedProvider = provider?.trim() ?? '';
    if (resolvedProvider.isEmpty) {
      resolvedProvider = officialProviderIdFor(resolvedCli) ?? '';
    }

    return SimpleLaunchIdentity(
      cli: resolvedCli,
      provider: resolvedProvider,
      model: model?.trim() ?? '',
      effort: effort?.trim() ?? '',
      presetId: presetId?.trim() ?? '',
    );
  }

  SimpleLaunchIdentity copyWith({
    CliTool? cli,
    String? provider,
    String? model,
    String? effort,
    String? presetId,
  }) {
    return SimpleLaunchIdentity(
      cli: cli ?? this.cli,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      effort: effort ?? this.effort,
      presetId: presetId ?? this.presetId,
    );
  }

}
