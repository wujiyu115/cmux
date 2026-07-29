import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_project_config.dart';

void main() {
  test('round-trips extension overrides', () {
    const config = WorkspaceProjectConfig(
      extensionOverrides: {'rtk': false},
    );
    final restored = WorkspaceProjectConfig.fromJson(config.toJson());
    expect(restored, config);
  });

  test('effectiveExtensionEnabled honors override then global', () {
    const config = WorkspaceProjectConfig(extensionOverrides: {'rtk': false});
    expect(
      config.effectiveExtensionEnabled(
        extensionId: 'rtk',
        globalEnabled: {'rtk', 'codegraph'},
      ),
      isFalse,
    );
    expect(
      config.effectiveExtensionEnabled(
        extensionId: 'codegraph',
        globalEnabled: {'rtk', 'codegraph'},
      ),
      isTrue,
    );
  });
}
