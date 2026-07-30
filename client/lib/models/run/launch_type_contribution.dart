import 'package:flutter/foundation.dart';

/// Adapter process lifecycle declared by a `launch-type` extension effect.
enum LaunchAdapterLifecycle {
  sticky,
  oneshot,
}

/// A registered launch type from a built-in definition or extension effect.
@immutable
class LaunchTypeContribution {
  const LaunchTypeContribution({
    this.extensionId,
    required this.type,
    required this.kinds,
    required this.adapterCommand,
    required this.adapterRuntime,
    required this.lifecycle,
    required this.configurationSchema,
    this.discover,
  });

  /// Null for built-in types such as `process`.
  final String? extensionId;
  final String type;
  final List<String> kinds;
  final String adapterCommand;
  final String adapterRuntime;
  final LaunchAdapterLifecycle lifecycle;
  final Map<String, Object?> configurationSchema;
  final Map<String, Object?>? discover;

  /// Whether this type participates in glob-based project discover (v1).
  bool get isDiscoverEnabled => discover?['enabled'] == true;

  /// Glob patterns relative to each workspace folder root.
  List<String> get discoverGlobs {
    final raw = discover?['globs'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item != null) item.toString().trim(),
    ].where((pattern) => pattern.isNotEmpty).toList();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaunchTypeContribution &&
          runtimeType == other.runtimeType &&
          extensionId == other.extensionId &&
          type == other.type &&
          listEquals(kinds, other.kinds) &&
          adapterCommand == other.adapterCommand &&
          adapterRuntime == other.adapterRuntime &&
          lifecycle == other.lifecycle &&
          mapEquals(configurationSchema, other.configurationSchema) &&
          mapEquals(discover, other.discover);

  @override
  int get hashCode => Object.hash(
    extensionId,
    type,
    Object.hashAll(kinds),
    adapterCommand,
    adapterRuntime,
    lifecycle,
    Object.hashAll(configurationSchema.entries),
    discover == null ? null : Object.hashAll(discover!.entries),
  );
}
