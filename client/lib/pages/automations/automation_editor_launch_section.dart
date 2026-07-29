import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../pages/home_workspace/workspace/workspace_landing_location_fields.dart';
import 'package:shared_ui/shared_ui.dart';

/// Launch parameters for launch-prompt automations — mirrors landing compose.
class AutomationEditorLaunchSection extends StatelessWidget {
  const AutomationEditorLaunchSection({
    required this.workspace,
    required this.projectFolderPath,
    required this.workingDirectoryPath,
    required this.dangerouslySkipPermissions,
    required this.labelWidth,
    required this.onProjectChanged,
    required this.onWorktreeChanged,
    required this.onPermissionsChanged,
    super.key,
  });

  final Workspace workspace;
  final String? projectFolderPath;
  final String? workingDirectoryPath;
  final bool dangerouslySkipPermissions;
  final double labelWidth;
  final ValueChanged<String?> onProjectChanged;
  final ValueChanged<String?> onWorktreeChanged;
  final ValueChanged<bool> onPermissionsChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkspaceLandingLocationFields(
          workspace: workspace,
          projectFolderPath: projectFolderPath,
          workingDirectoryPath: workingDirectoryPath,
          labelWidth: labelWidth,
          onProjectChanged: onProjectChanged,
          onWorktreeChanged: onWorktreeChanged,
        ),
        const SizedBox(height: 12),
        TpFormField<bool>(
          key: ValueKey('permissions-$dangerouslySkipPermissions'),
          id: 'dangerouslySkipPermissions',
          initialValue: dangerouslySkipPermissions,
          label: Text(l10n.automationsPermissions),
          layoutStyle: TpFormFieldLayoutStyle.inline,
          labelWidth: labelWidth,
          builder: (state) {
            return TpSelect<bool>(
              items: const [false, true],
              initialItem: state.value ?? false,
              decoration: TpSelectDecorations.themed(context),
              itemLabel: (value) => value
                  ? l10n.workspaceChatLandingFullAccessPermissions
                  : l10n.workspaceChatLandingDefaultPermissions,
              onChanged: (value) {
                if (value == null) return;
                state.didChange(value);
                onPermissionsChanged(value);
              },
            );
          },
        ),
      ],
    );
  }
}
