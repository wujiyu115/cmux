import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/mobile_toolbar_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/toolbar_key.dart';
import '../../../utils/ui/app_keys.dart';
import 'mobile_toolbar_labels.dart';

/// Lets the user decide which key groups the toolbar shows and in what order.
///
/// A phone bar only fits a handful of groups, so ordering *is* the feature: drag
/// the groups you use to the top and raise the visible count until the bar is as
/// busy as you like.
class MobileToolbarCustomizePage extends StatelessWidget {
  const MobileToolbarCustomizePage({super.key});

  /// Route helper so callers cannot forget to re-provide the cubit across the
  /// route boundary.
  static Route<void> route(MobileToolbarCubit cubit) => MaterialPageRoute(
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: const MobileToolbarCustomizePage(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final spacing = context.tpSpacing;
    final cubit = context.read<MobileToolbarCubit>();
    return Scaffold(
      key: AppKeys.mobileToolbarCustomizePage,
      appBar: AppBar(
        title: Text(l10n.mobileToolbarCustomize),
        actions: [
          TpIconButton(
            key: AppKeys.mobileToolbarResetButton,
            icon: Icons.restart_alt,
            tooltip: l10n.mobileToolbarReset,
            onTap: cubit.resetLayout,
          ),
          SizedBox(width: spacing.sm),
        ],
      ),
      body: BlocBuilder<MobileToolbarCubit, MobileToolbarState>(
        builder: (context, state) {
          final groupCount = state.groupOrder.length;
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.all(spacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.mobileToolbarVisibleGroups(
                          state.visibleGroupCount,
                        ),
                        style: styles.mdMedium,
                      ),
                    ),
                    // Tooltips preview the resulting count, so they must clamp the
                    // same way the cubit does or the buttons promise "0" and "17".
                    TpIconButton(
                      icon: Icons.remove,
                      tooltip: l10n.mobileToolbarVisibleGroups(
                        (state.visibleGroupCount - 1).clamp(1, groupCount),
                      ),
                      onTap: () => cubit.setVisibleGroupCount(
                        state.visibleGroupCount - 1,
                      ),
                    ),
                    SizedBox(width: spacing.sm),
                    TpIconButton(
                      icon: Icons.add,
                      tooltip: l10n.mobileToolbarVisibleGroups(
                        (state.visibleGroupCount + 1).clamp(1, groupCount),
                      ),
                      onTap: () => cubit.setVisibleGroupCount(
                        state.visibleGroupCount + 1,
                      ),
                    ),
                  ],
                ),
              ),
              if (state.mostUsedKeys.isNotEmpty)
                _MostUsed(keys: state.mostUsedKeys.take(8).toList()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(l10n.mobileToolbarReorderHint, style: styles.sm),
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: EdgeInsets.symmetric(vertical: spacing.md),
                  itemCount: state.groupOrder.length,
                  onReorder: (oldIndex, newIndex) => cubit.reorderGroups(
                    oldIndex,
                    // ReorderableListView reports the insertion index, which sits
                    // one too high for a downward drag; the cubit wants a
                    // post-removal index.
                    newIndex > oldIndex ? newIndex - 1 : newIndex,
                  ),
                  itemBuilder: (context, index) {
                    final id = state.groupOrder[index];
                    final group = toolbarGroupById(id);
                    final visible = index < state.visibleGroupCount;
                    final cs = Theme.of(context).colorScheme;
                    return ListTile(
                      key: AppKeys.mobileToolbarGroupTile(id),
                      leading: Icon(
                        visible ? Icons.visibility : Icons.visibility_off,
                        color: visible ? cs.primary : cs.onSurfaceVariant,
                      ),
                      title: Text(toolbarGroupLabel(id, l10n)),
                      subtitle: group == null
                          ? null
                          : Text(group.keys.map((k) => k.label).join('  ')),
                      trailing: const Icon(Icons.drag_handle),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The keys this user actually presses, so reordering is informed by data rather
/// than by guessing.
class _MostUsed extends StatelessWidget {
  const _MostUsed({required this.keys});

  final List<ToolbarKey> keys;

  @override
  Widget build(BuildContext context) {
    final spacing = context.tpSpacing;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.lg, 0, spacing.lg, spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.mobileToolbarMostUsed, style: styles.mdMedium),
          SizedBox(height: spacing.sm),
          Wrap(
            spacing: spacing.sm,
            runSpacing: spacing.sm,
            children: [
              for (final key in keys)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.sm,
                      vertical: spacing.xs,
                    ),
                    child: Text(key.label, style: styles.smMedium),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
