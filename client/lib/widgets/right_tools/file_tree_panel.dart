import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/file_tree_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/file_tree/file_tree_visible_rows.dart';
import '../../services/storage/runtime_context.dart';
import '../../utils/ui/app_keys.dart';
import '../file_tree_node.dart';
import 'file_tree_header_overflow_menu.dart';
import 'right_tools_lifecycle.dart';

/// Workspace file tree panel.
///
/// Pure view over an injected [FileTreeCubit] from [WorkspaceFileTreeStore].
///
/// A single workspace folder shows its children directly; multiple folders each
/// get a collapsible header (VSCode multi-root layout).
class FileTreePanel extends StatefulWidget {
  const FileTreePanel({
    required this.cubit,
    required this.workContext,
    required this.workspaceId,
    super.key,
  });

  final FileTreeCubit cubit;
  final RuntimeContext workContext;
  final String workspaceId;

  @override
  State<FileTreePanel> createState() => _FileTreePanelState();
}

class _FileTreePanelState extends State<FileTreePanel> {
  final _filterController = TextEditingController();
  final _listScrollController = ScrollController();
  final _horizontalScrollController = ScrollController();
  bool _filterVisible = false;
  bool _listReady = false;

  /// (cubit, roots) pair whose retained offset was already restored by this
  /// panel instance — restoring twice would fight the user's own scrolling.
  ({FileTreeCubit cubit, List<String> roots})? _restoredScrollKey;

  static const int _restoreScrollAttempts = 30;

  FileTreeCubit get _cubit => widget.cubit;

  @override
  void initState() {
    super.initState();
    // Filter lives in the cubit; sync the text field when the panel remounts.
    _filterController.text = _cubit.state.filterText;
    // Stagger list mount one frame after the header so first paint stays light.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      RightToolsLifecycle.of(context).ensureFileTreeReady();
      setState(() => _listReady = true);
      _scheduleRestoreScroll();
    });
  }

  @override
  void didUpdateWidget(covariant FileTreePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cubit != widget.cubit) {
      // Cubit swap (storage-target change): restore the new cubit's offset.
      _restoredScrollKey = null;
      _scheduleRestoreScroll();
    }
  }

  void _toggleFilterVisible() {
    setState(() {
      _filterVisible = !_filterVisible;
      if (!_filterVisible) {
        _filterController.clear();
        _cubit.setFilter('');
      }
    });
  }

  Future<void> _revealActiveEditorFile() async {
    if (!mounted) return;
    final active = context.read<WorkbenchCubit>().activeTabId(
      widget.workspaceId,
    );
    if (active == null || active.kind != WorkbenchTabKind.file) return;

    _filterController.clear();
    final ok = await _cubit.revealPath(active.id);
    if (!mounted) return;
    if (!ok) {
      AppToast.show(
        context,
        message: context.l10n.fileTreeRevealFailed,
        variant: TpToastVariant.error,
      );
      return;
    }
    _scheduleRevealScroll();
  }

  void _scheduleRevealScroll([int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final target = _cubit.state.revealPath;
      if (target == null) return;

      if (!_listScrollController.hasClients) {
        if (attempt < 12) {
          _scheduleRevealScroll(attempt + 1);
        }
        return;
      }

      final rows = _cubit.state.visibleRows;
      final index = visibleRowIndexForPath(
        rows,
        target,
        _cubit.fsFor(target).pathContext,
      );
      if (index == null) {
        if (attempt < 12) {
          _scheduleRevealScroll(attempt + 1);
        } else if (mounted) {
          _cubit.clearRevealPath();
        }
        return;
      }

      final position = _listScrollController.position;
      final viewport = position.viewportDimension;
      final rowTop = index * kFileTreeRowExtent;
      final targetOffset = (rowTop - viewport * 0.35).clamp(
        0.0,
        position.maxScrollExtent,
      );
      await _listScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      if (mounted) {
        _cubit.clearRevealPath();
      }
    });
  }

  /// Restores [FileTreeCubit.retainedListScrollOffset] once the list has
  /// clients and tall enough content. Rows (re)load asynchronously after root
  /// mounts or filter clears, so retry across frames — same shape as
  /// [_scheduleRevealScroll].
  void _scheduleRestoreScroll([int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cubit = _cubit;
      final key = (cubit: cubit, roots: cubit.state.rootPaths);
      if (_restoredScrollKey == key) return;
      final target = cubit.retainedListScrollOffset;
      if (target <= 0) {
        _restoredScrollKey = key;
        return;
      }
      if (!_listScrollController.hasClients) {
        if (attempt < _restoreScrollAttempts) {
          _scheduleRestoreScroll(attempt + 1);
        }
        return;
      }
      final position = _listScrollController.position;
      if (position.maxScrollExtent < target &&
          attempt < _restoreScrollAttempts) {
        // Rows are still loading; wait for the content to grow.
        _scheduleRestoreScroll(attempt + 1);
        return;
      }
      _restoredScrollKey = key;
      if ((position.pixels - target).abs() < 0.5) return;
      _listScrollController.jumpTo(target.clamp(0.0, position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    _listScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return BlocProvider.value(
      value: _cubit,
      child: BlocListener<FileTreeCubit, FileTreeState>(
        listenWhen: (previous, next) =>
            !listEquals(previous.rootPaths, next.rootPaths) ||
            (previous.filterText.isNotEmpty && next.filterText.isEmpty),
        listener: (context, state) {
          // Root remounts replace the tree state (rows shrink then reload) and
          // a cleared filter un-clamps the position — both want the retained
          // offset back once rows settle.
          _restoredScrollKey = null;
          _scheduleRestoreScroll();
        },
        child: Container(
          key: AppKeys.fileTreePanel,
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BlocSelector<FileTreeCubit, FileTreeState, (bool, bool, String)>(
                selector: (state) => (
                  state.expandedPaths.isNotEmpty,
                  state.showHiddenFiles,
                  state.rootPath,
                ),
                builder: (context, header) {
                  final (hasExpandedFolders, showHiddenFiles, rootPath) =
                      header;
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      const actionSlotWidth = 28.0;
                      final actionCount = (hasExpandedFolders ? 5 : 4) + 1;
                      final showInlineActions =
                          constraints.maxWidth >= actionSlotWidth * actionCount;
                      return Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.fileTree,
                              style: TpTextStyles.of(
                                context,
                              ).xsBoldWideColored(cs.onSurfaceVariant),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          if (showInlineActions)
                            ..._buildFileTreeHeaderActions(
                              l10n: l10n,
                              showHiddenFiles: showHiddenFiles,
                              rootPath: rootPath,
                              filterVisible: _filterVisible,
                            )
                          else
                            FileTreeHeaderOverflowMenu(
                              l10n: l10n,
                              showHiddenFiles: showHiddenFiles,
                              filterVisible: _filterVisible,
                              hasExpandedFolders: hasExpandedFolders,
                              canCopy: rootPath.isNotEmpty,
                              onRefresh: _cubit.refresh,
                              onReveal: () =>
                                  unawaited(_revealActiveEditorFile()),
                              onCollapseAll: _cubit.collapseAllFolders,
                              onToggleFilter: _toggleFilterVisible,
                              onToggleHidden: _cubit.toggleShowHidden,
                              onCopy: () {
                                if (rootPath.isNotEmpty) {
                                  Clipboard.setData(
                                    ClipboardData(text: rootPath),
                                  );
                                }
                              },
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_filterVisible) ...[
                      _FileTreeFilterField(
                        controller: _filterController,
                        hintText: l10n.filterFiles,
                        onFilterChanged: _cubit.setFilter,
                        onClear: () {
                          _filterController.clear();
                          _cubit.setFilter('');
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_listReady) ...[
                      // Single-root: show the folder path. Multi-root: each root
                      // gets its own header row, so the single path line is hidden.
                      BlocSelector<
                        FileTreeCubit,
                        FileTreeState,
                        (bool, bool, String)
                      >(
                        selector: (state) => (
                          state.isMultiRoot,
                          state.anyRootExists,
                          state.rootPath,
                        ),
                        builder: (context, root) {
                          final (isMultiRoot, anyRootExists, rootPath) = root;
                          if (isMultiRoot) return const SizedBox.shrink();
                          if (anyRootExists) {
                            return Text(
                              rootPath,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TpTextStyles.of(
                                context,
                              ).smColored(cs.onSurfaceVariant),
                            );
                          }
                          return Text(
                            'Directory unavailable',
                            style: TpTextStyles.of(context).smColored(
                              cs.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child:
                            BlocSelector<
                              FileTreeCubit,
                              FileTreeState,
                              List<FileTreeVisibleRow>
                            >(
                              selector: (state) => state.visibleRows,
                              builder: (context, rows) {
                                if (!context
                                    .read<FileTreeCubit>()
                                    .state
                                    .anyRootExists) {
                                  return const SizedBox.shrink();
                                }
                                return _FileTreeList(
                                  rows: rows,
                                  cubit: _cubit,
                                  textColor: cs.onSurface,
                                  listScrollController: _listScrollController,
                                  horizontalScrollController:
                                      _horizontalScrollController,
                                  desktopShellActions: _desktopShellActionsFor(
                                    _workContext,
                                  ),
                                  remoteFileManagerActions:
                                      _remoteFileManagerActionsFor(
                                        _workContext,
                                      ),
                                  workContext: _workContext,
                                  workspaceId: widget.workspaceId,
                                );
                              },
                            ),
                      ),
                    ] else
                      const Expanded(child: SizedBox.shrink()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFileTreeHeaderActions({
    required AppLocalizations l10n,
    required bool showHiddenFiles,
    required String rootPath,
    required bool filterVisible,
  }) {
    final actions = <Widget>[
      TpIconButton(
        icon: filterVisible ? Icons.search_off : Icons.search,
        compact: true,
        size: TpIconButton.kCompactSize,
        tooltip: filterVisible
            ? l10n.fileTreeHideFilter
            : l10n.fileTreeShowFilter,
        onTap: _toggleFilterVisible,
      ),
      TpIconButton(
        icon: Icons.refresh,
        compact: true,
        size: TpIconButton.kCompactSize,
        tooltip: l10n.fileTreeRefresh,
        onTap: _cubit.refresh,
      ),
      TpIconButton(
        icon: Icons.my_location_outlined,
        compact: true,
        size: TpIconButton.kCompactSize,
        tooltip: l10n.fileTreeRevealActiveFile,
        onTap: () => unawaited(_revealActiveEditorFile()),
      ),
    ];
    actions.add(
      TpIconButton(
        icon: Icons.unfold_less,
        compact: true,
        size: TpIconButton.kCompactSize,
        tooltip: l10n.treeCollapseAllFolders,
        onTap: _cubit.collapseAllFolders,
      ),
    );
    actions.addAll([
      TpIconButton(
        icon: showHiddenFiles
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        compact: true,
        size: TpIconButton.kCompactSize,
        tooltip: showHiddenFiles ? 'Hide hidden files' : 'Show hidden files',
        onTap: _cubit.toggleShowHidden,
      ),
      TpIconButton(
        icon: Icons.copy,
        iconSize: context.tpIconSizes.md,
        size: TpIconButton.kCompactSize,
        tooltip: l10n.copy,
        onTap: () {
          if (rootPath.isNotEmpty) {
            Clipboard.setData(ClipboardData(text: rootPath));
          }
        },
      ),
    ]);
    return actions;
  }

  RuntimeContext get _workContext => widget.workContext;

  bool _desktopShellActionsFor(RuntimeContext ctx) {
    if (kIsWeb) return false;
    return ctx.mode == StorageBackendMode.native ||
        ctx.mode == StorageBackendMode.wsl;
  }

  bool _remoteFileManagerActionsFor(RuntimeContext ctx) {
    if (kIsWeb) return false;
    return ctx.mode == StorageBackendMode.ssh;
  }
}

/// Filter row isolated from the file tree list so keystrokes do not rebuild rows.
class _FileTreeFilterField extends StatelessWidget {
  const _FileTreeFilterField({
    required this.controller,
    required this.hintText,
    required this.onFilterChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: Icon(Icons.search, size: context.tpIconSizes.md),
            floatingLabelBehavior: FloatingLabelBehavior.never,
            suffixIcon: value.text.isNotEmpty
                ? TpIconButton(
                    icon: Icons.clear,
                    compact: true,
                    size: TpIconButton.kCompactSize,
                    onTap: onClear,
                  )
                : null,
          ),
          onChanged: onFilterChanged,
        );
      },
    );
  }
}

class _FileTreeList extends StatefulWidget {
  const _FileTreeList({
    required this.rows,
    required this.cubit,
    required this.textColor,
    required this.listScrollController,
    required this.horizontalScrollController,
    required this.desktopShellActions,
    required this.remoteFileManagerActions,
    required this.workContext,
    required this.workspaceId,
  });

  final List<FileTreeVisibleRow> rows;
  final FileTreeCubit cubit;
  final Color textColor;
  final ScrollController listScrollController;
  final ScrollController horizontalScrollController;
  final bool desktopShellActions;
  final bool remoteFileManagerActions;
  final RuntimeContext workContext;
  final String workspaceId;

  @override
  State<_FileTreeList> createState() => _FileTreeListState();
}

class _FileTreeListState extends State<_FileTreeList> {
  var _hoverEnabled = true;
  var _activeScrolls = 0;

  bool _desktopShellActionsFor(RuntimeContext ctx) {
    if (kIsWeb) return false;
    return ctx.mode == StorageBackendMode.native ||
        ctx.mode == StorageBackendMode.wsl;
  }

  bool _remoteFileManagerActionsFor(RuntimeContext ctx) {
    if (kIsWeb) return false;
    return ctx.mode == StorageBackendMode.ssh;
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      // Track the offset only outside filtered views: their short row lists
      // clamp the position, which would clobber the retained full-tree offset.
      if (widget.cubit.state.filterText.isEmpty) {
        widget.cubit.setListScrollOffset(notification.metrics.pixels);
      }
    }
    if (notification is ScrollStartNotification) {
      _activeScrolls++;
      if (_hoverEnabled) setState(() => _hoverEnabled = false);
      return false;
    }
    if (notification is ScrollEndNotification) {
      _activeScrolls = (_activeScrolls - 1).clamp(0, 1 << 30);
      if (_activeScrolls == 0 && !_hoverEnabled) {
        setState(() => _hoverEnabled = true);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    if (rows.isEmpty) {
      return Text(
        '(empty)',
        style: TpTextStyles.of(
          context,
        ).smColored(widget.textColor.withValues(alpha: 0.35)),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelStyle = TpTextStyles.of(context).md;
        final emptyLabelStyle = TpTextStyles.of(context).xs;
        final contentWidth = math.max(
          constraints.maxWidth,
          fileTreeMinContentWidth(
            rows: rows,
            labelStyle: labelStyle,
            emptyLabelStyle: emptyLabelStyle,
            textScaler: MediaQuery.textScalerOf(context),
          ),
        );

        return Scrollbar(
          controller: widget.horizontalScrollController,
          thumbVisibility: true,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: widget.horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth,
              height: constraints.maxHeight,
              child: Scrollbar(
                controller: widget.listScrollController,
                thumbVisibility: true,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScrollNotification,
                  child: ListView.builder(
                    scrollCacheExtent: ScrollCacheExtent.pixels(400),
                    controller: widget.listScrollController,
                    itemCount: rows.length,
                    itemExtent: kFileTreeRowExtent,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      if (row.isEmptyPlaceholder) {
                        return SizedBox(
                          width: contentWidth,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: kFileTreeRowVerticalPadding,
                              horizontal: kFileTreeRowHorizontalPadding,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left:
                                      row.depth * kFileTreeIndentWidth +
                                      kFileTreeNodePaddingLeft +
                                      kFileTreeChevronSlotWidth,
                                ),
                                child: Text(
                                  '(empty)',
                                  style: TpTextStyles.of(context).xs.copyWith(
                                    color: widget.textColor.withValues(
                                      alpha: 0.35,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      return SizedBox(
                        width: contentWidth,
                        child: FileTreeNode(
                          key: ValueKey(
                            row.isRoot ? 'root:${row.path}' : row.path,
                          ),
                          path: row.path,
                          entry: row.entry,
                          depth: row.depth,
                          cubit: widget.cubit,
                          textColor: widget.textColor,
                          workspaceId: widget.workspaceId,
                          desktopShellActions: _desktopShellActionsFor(
                            widget.cubit.workContextFor(row.path) ??
                                widget.workContext,
                          ),
                          remoteFileManagerActions:
                              _remoteFileManagerActionsFor(
                                widget.cubit.workContextFor(row.path) ??
                                    widget.workContext,
                              ),
                          workContext:
                              widget.cubit.workContextFor(row.path) ??
                              widget.workContext,
                          hoverEnabled: _hoverEnabled,
                          isRoot: row.isRoot,
                          rootMissing: row.rootMissing,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
