import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';

class LayoutRegionVisibilitySection extends StatelessWidget {
  const LayoutRegionVisibilitySection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<LayoutCubit>();

    return BlocSelector<LayoutCubit, LayoutState, (bool, bool, bool)>(
      selector: (state) => (
        state.preferences.fileTreeVisible,
        state.preferences.gitVisible,
        state.preferences.searchVisible,
      ),
      builder: (context, visibility) {
        final (fileTreeVisible, gitVisible, searchVisible) = visibility;

        void setVisibility({
          bool? fileTreeVisible,
          bool? gitVisible,
          bool? searchVisible,
        }) {
          controller.setRegionVisibility(
            appRailVisible: true,
            fileTreeVisible: fileTreeVisible ?? visibility.$1,
            gitVisible: gitVisible ?? visibility.$2,
            searchVisible: searchVisible ?? visibility.$3,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpSectionHeader(title: l10n.regionVisibility),
            TpPreferenceRow(
              title: l10n.fileTree,
              subtitle: l10n.visibilityFileTreeHint,
              trailing: Switch(
                key: AppKeys.fileTreeVisibilitySwitch,
                value: fileTreeVisible,
                onChanged: (value) => setVisibility(fileTreeVisible: value),
              ),
              showDividerBelow: true,
            ),
            TpPreferenceRow(
              title: l10n.sourceControl,
              subtitle: l10n.visibilityGitHint,
              trailing: Switch(
                value: gitVisible,
                onChanged: (value) => setVisibility(gitVisible: value),
              ),
              showDividerBelow: true,
            ),
            TpPreferenceRow(
              title: l10n.searchInFilesLabel,
              subtitle: l10n.visibilitySearchHint,
              trailing: Switch(
                key: AppKeys.searchVisibilitySwitch,
                value: searchVisible,
                onChanged: (value) => setVisibility(searchVisible: value),
              ),
              showDividerBelow: false,
            ),
          ],
        );
      },
    );
  }
}
