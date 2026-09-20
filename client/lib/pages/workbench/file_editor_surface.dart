import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/editor_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/commands/command_bus.dart';
import '../../services/commands/editor_goto_line_command_registrar.dart';
import '../../services/commands/editor_goto_symbol_command_registrar.dart';
import '../../services/editor/editor_symbols.dart';
import '../../services/editor/file_editor_theme.dart';
import '../../services/editor/file_editor_toolbar.dart';
import '../../services/editor/markdown_view_mode_store.dart';
import '../../services/editor_platform/document_session.dart';
import '../../services/editor_platform/editor_viewport_token_binder.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/workspace/workspace_path_utils.dart';
import '../../widgets/workbench/code_find_panel.dart';
import '../../widgets/workbench/file_diff_surface_toggle.dart';
import '../../widgets/workbench/markdown_view_mode_toggle.dart';
import 'file_editor_image_preview.dart';
import 'editor_goto_line_dialog.dart';
import 'editor_symbol_sheet.dart';
import 'markdown_preview_pane.dart';

/// Center-pane file editor for one path (no inner tab bar).
class FileEditorSurface extends StatelessWidget {
  const FileEditorSurface({
    required this.workspaceId,
    required this.path,
    super.key,
  });

  final String workspaceId;
  final String path;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (isImagePreviewPath(path)) {
      return ColoredBox(
        color: cs.workspaceCard,
        child: FileEditorImagePreview(workspaceId: workspaceId, path: path),
      );
    }
    return BlocListener<EditorCubit, EditorState>(
      listenWhen: (prev, next) {
        final wasDirty = prev.bucket(workspaceId).isDirty(path);
        final isDirty = next.bucket(workspaceId).isDirty(path);
        return !wasDirty && isDirty;
      },
      listener: (context, state) {
        context.read<WorkbenchCubit>().pinTab(
          workspaceId,
          WorkbenchTabId.file(path),
        );
      },
      child: ColoredBox(
        color: cs.workspaceCard,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FileEditorToolbar(workspaceId: workspaceId, path: path),
            const Divider(height: 1),
            Expanded(
              child: _FileEditorBody(workspaceId: workspaceId, path: path),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileEditorToolbar extends StatelessWidget {
  const _FileEditorToolbar({required this.workspaceId, required this.path});

  final String workspaceId;
  final String path;

  /// [LayoutCubit] when in scope (app shell); null in lightweight harnesses.
  LayoutCubit? _maybeLayoutCubit(BuildContext context) {
    try {
      return context.read<LayoutCubit>();
    } on Object {
      return null;
    }
  }

  /// Toolbar path: resolve the open file's controller, then show the picker.
  void _openGotoSymbolForToolbar(BuildContext context) {
    final controller =
        context.read<EditorCubit>().controllerFor(workspaceId, path);
    if (controller == null) return;
    unawaited(
      showEditorSymbolSheet(context, controller: controller, path: path),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dirty = context.select<EditorCubit, bool>(
      (c) => c.state.bucket(workspaceId).isDirty(path),
    );
    final readOnly = context.select<EditorCubit, bool>(
      (c) => c.isReadOnly(workspaceId, path),
    );
    final name = p.basename(path);
    final cs = Theme.of(context).colorScheme;
    // Muted directory breadcrumb beside the file name so same-named files in
    // different folders are distinguishable once opened.
    final scope = WorkspaceToolsScope.maybeOf(context);
    final relative = scope == null
        ? null
        : relativePathWithinRoots(scope.roots, path);
    // Show only the directory part: the file name itself is already bold.
    final relativeDir = relative == null || relative == name
        ? null
        : p.posix.dirname(relative);
    final canToggleDiff = gitCubitForAbsolutePath(context, path) != null;
    final isMarkdown = isMarkdownEditorPath(path);
    final opener = context.read<WorkbenchEditorOpener>();
    // [LayoutCubit] lives above the app shell; lightweight test harnesses
    // mount the editor without it and default to no wrap.
    final LayoutCubit? layout = _maybeLayoutCubit(context);
    final wordWrap = layout == null
        ? false
        : context.select<LayoutCubit, bool>(
            (c) => c.state.preferences.editorWordWrap,
          );
    return SizedBox(
      height: 36,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: Tooltip(
                message: relative ?? path,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        dirty ? '$name •' : name,
                        style: TpTextStyles.of(context).mdSemibold,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (relativeDir != null && relativeDir != '.') ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          relativeDir,
                          style: TpTextStyles.of(context).xsColored(
                            cs.onSurfaceVariant.withValues(alpha: 0.8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: context.l10n.editorWordWrap,
              icon: Icon(
                Icons.wrap_text,
                size: 18,
                color: wordWrap ? cs.primary : cs.onSurfaceVariant,
              ),
              onPressed: layout == null
                  ? null
                  : () => layout.setEditorWordWrap(!wordWrap),
            ),
            IconButton(
              tooltip: context.l10n.editorGotoSymbolTitle,
              icon: const Icon(Icons.format_list_numbered, size: 18),
              onPressed: () => _openGotoSymbolForToolbar(context),
            ),
            if (!readOnly) ...[
              IconButton(
                tooltip: context.l10n.editorSave,
                icon: const Icon(Icons.save_outlined, size: 18),
                onPressed: () => unawaited(
                  context.read<EditorCubit>().saveFile(workspaceId, path),
                ),
              ),
              IconButton(
                tooltip: context.l10n.editorRevertChanges,
                icon: const Icon(Icons.undo, size: 18),
                onPressed: dirty
                    ? () => context.read<EditorCubit>().revertFile(
                        workspaceId,
                        path,
                      )
                    : null,
              ),
            ],
            if (isMarkdown) ...[
              const SizedBox(width: 4),
              ListenableBuilder(
                listenable: opener.markdownViewModes,
                builder: (context, _) {
                  return MarkdownViewModeToggle(
                    mode: opener.markdownViewModes.modeFor(path),
                    onModeChanged: (mode) =>
                        opener.markdownViewModes.setMode(path, mode),
                  );
                },
              ),
            ],
            if (canToggleDiff) ...[
              const SizedBox(width: 4),
              FileDiffSurfaceToggle(
                mode: FileDiffSurfaceMode.file,
                onModeChanged: (mode) {
                  if (mode == FileDiffSurfaceMode.diff) {
                    unawaited(
                      switchFileDiffSurface(
                        context: context,
                        workspaceId: workspaceId,
                        absolutePath: path,
                        target: mode,
                      ),
                    );
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FileEditorBody extends StatelessWidget {
  const _FileEditorBody({required this.workspaceId, required this.path});

  final String workspaceId;
  final String path;

  @override
  Widget build(BuildContext context) {
    final model = context.select<EditorCubit, _FileBodyModel>(
      (c) => _FileBodyModel.from(c.state.bucket(workspaceId), path),
    );
    final l10n = context.l10n;

    if (model.isLoading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (model.loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.editorPanelErrorMessage(model.loadError!),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final editor = context.read<EditorCubit>();
    final controller = editor.controllerFor(workspaceId, path);
    if (controller == null) {
      return Center(child: Text(l10n.editorNotReady));
    }

    if (!isMarkdownEditorPath(path)) {
      return _CodeEditorPane(
        workspaceId: workspaceId,
        path: path,
        controller: controller,
        readOnly: model.readOnly,
      );
    }

    final opener = context.read<WorkbenchEditorOpener>();
    return ListenableBuilder(
      listenable: opener.markdownViewModes,
      builder: (context, _) {
        final mode = opener.markdownViewModes.modeFor(path);
        if (mode == MarkdownViewMode.preview) {
          return MarkdownPreviewPane(
            workspaceId: workspaceId,
            path: path,
            controller: controller,
          );
        }
        return _CodeEditorPane(
          workspaceId: workspaceId,
          path: path,
          controller: controller,
          readOnly: model.readOnly,
        );
      },
    );
  }
}

class _CodeEditorPane extends StatefulWidget {
  const _CodeEditorPane({
    required this.workspaceId,
    required this.path,
    required this.controller,
    required this.readOnly,
  });

  final String workspaceId;
  final String path;
  final CodeLineEditingController controller;
  final bool readOnly;

  /// Soft-wrap preference via [LayoutCubit]; lightweight harnesses without
  /// the cubit fall back to off.
  static bool _selectWordWrap(BuildContext context) {
    try {
      return context.select<LayoutCubit, bool>(
        (c) => c.state.preferences.editorWordWrap,
      );
    } on Object {
      return false;
    }
  }

  @override
  State<_CodeEditorPane> createState() => _CodeEditorPaneState();
}

class _CodeEditorPaneState extends State<_CodeEditorPane> {
  final _menuOpen = ValueNotifier(false);
  final FocusNode _focusNode = FocusNode(debugLabel: 'code-editor-pane');

  /// Find/replace state for this pane. Owned here (not by re-editor) so it
  /// survives editor rebuilds; re-editor only disposes controllers it created
  /// itself.
  late final CodeFindController _findController =
      CodeFindController(widget.controller);

  /// Captured in [initState] so scroll listeners keep a valid reference after
  /// the element starts deactivating.
  late final EditorCubit _editor;

  /// External scroll anchors: the pane is unmounted when its tab is
  /// de-selected, so re-editor's internal controller would drop the viewport
  /// offset. We own the controllers, seed them with the last persisted offset,
  /// and write every pixel change back into [EditorCubit].
  late final ScrollController _verticalScroller;
  late final ScrollController _horizontalScroller;
  late final CodeScrollController _scrollController;

  /// Whether this pane already claimed focus in this mount. Focus-on-mount
  /// only runs once: the pane mounts when its file tab becomes active, and a
  /// later widget rebuild (word-wrap toggle, find panel opening) must not
  /// steal focus from a surface the user focused meanwhile.
  bool _claimedFocus = false;

  @override
  void initState() {
    super.initState();
    _editor = context.read<EditorCubit>();
    final anchors = _editor.codeScrollOffsetFor(
      widget.workspaceId,
      widget.path,
    );
    _verticalScroller = ScrollController(
      initialScrollOffset: anchors.vertical,
    );
    _horizontalScroller = ScrollController(
      initialScrollOffset: anchors.horizontal,
    );
    _verticalScroller.addListener(_persistScroll);
    _horizontalScroller.addListener(_persistScroll);
    _scrollController = CodeScrollController(
      verticalScroller: _verticalScroller,
      horizontalScroller: _horizontalScroller,
    );
    _editor.registerCodeFocusNode(
      widget.workspaceId,
      widget.path,
      _focusNode,
    );
  }

  @override
  void didUpdateWidget(_CodeEditorPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      // The same code pane is re-targeted at a different document: the
      // registration must follow the new path.
      _editor.unregisterCodeFocusNode(
        oldWidget.workspaceId,
        oldWidget.path,
        _focusNode,
      );
      _editor.registerCodeFocusNode(
        widget.workspaceId,
        widget.path,
        _focusNode,
      );
    }
  }

  void _claimFocusOnce() {
    if (_claimedFocus) return;
    _claimedFocus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.canRequestFocus) return;
      _focusNode.requestFocus();
    });
  }

  void _persistScroll() {
    if (_verticalScroller.hasClients) {
      _editor.setCodeScrollOffset(
        widget.workspaceId,
        widget.path,
        vertical: _verticalScroller.position.pixels,
      );
    }
    if (_horizontalScroller.hasClients) {
      _editor.setCodeScrollOffset(
        widget.workspaceId,
        widget.path,
        horizontal: _horizontalScroller.position.pixels,
      );
    }
  }

  /// Go-to-line (Mod+G) and go-to-symbol (Mod+Shift+O) claims, held while
  /// this pane's subtree has focus so the shortcuts always target the
  /// focused editor — kept-alive workspace tabs can leave several panes
  /// mounted offstage.
  VoidCallback? _gotoLineDisposer;
  bool _gotoLineOpen = false;
  VoidCallback? _gotoSymbolDisposer;
  bool _gotoSymbolOpen = false;

  void _setMenuOpen(bool value) {
    if (mounted) _menuOpen.value = value;
  }

  void _setGotoLineClaim(bool active) {
    if (active) {
      if (_gotoLineDisposer != null) return;
      _gotoLineDisposer = claimEditorGotoLineCommand(
        context.read<CommandBus>(),
        _openGotoLine,
      );
      _gotoSymbolDisposer ??= claimEditorGotoSymbolCommand(
        context.read<CommandBus>(),
        _openGotoSymbol,
      );
    } else {
      _gotoLineDisposer?.call();
      _gotoLineDisposer = null;
      _gotoSymbolDisposer?.call();
      _gotoSymbolDisposer = null;
    }
  }

  void _openGotoSymbol() {
    if (_gotoSymbolOpen || !mounted) return;
    _gotoSymbolOpen = true;
    unawaited(
      showEditorSymbolSheet(
        context,
        controller: widget.controller,
        path: widget.path,
      ).whenComplete(() {
        if (mounted) _gotoSymbolOpen = false;
      }),
    );
  }

  void _openGotoLine() {
    if (_gotoLineOpen || !mounted) return;
    _gotoLineOpen = true;
    unawaited(
      showEditorGotoLineDialog(
        context,
        controller: widget.controller,
      ).whenComplete(() {
        if (mounted) _gotoLineOpen = false;
      }),
    );
  }

  @override
  void dispose() {
    _gotoLineDisposer?.call();
    _gotoSymbolDisposer?.call();
    _editor.unregisterCodeFocusNode(
      widget.workspaceId,
      widget.path,
      _focusNode,
    );
    // focusChange auto-save: the pane unmounting means its file tab lost
    // the active slot.
    _editor.maybeSaveOnBlur(widget.workspaceId, widget.path);
    _verticalScroller.removeListener(_persistScroll);
    _horizontalScroller.removeListener(_persistScroll);
    // CodeScrollController.dispose only unbinds the editor key; the injected
    // ScrollControllers are ours to release.
    _scrollController.dispose();
    _verticalScroller.dispose();
    _horizontalScroller.dispose();
    _findController.dispose();
    _menuOpen.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _claimFocusOnce();
    final editor = context.read<EditorCubit>();
    final codeEditor = CodeEditor(
      key:
          editor.editorKeyFor(widget.workspaceId, widget.path) ??
          ValueKey(widget.path),
      controller: widget.controller,
      readOnly: widget.readOnly,
      focusNode: _focusNode,
      findController: _findController,
      scrollController: _scrollController,
      findBuilder: (context, controller, readOnly) =>
          CodeFindPanel(controller: controller, readOnly: readOnly),
      toolbarController: FileEditorContextMenuController(
        onMenuOpenChanged: _setMenuOpen,
        workspaceId: widget.workspaceId,
        filePath: widget.path,
      ),
      style: codeEditorStyleFor(
        context,
        widget.path,
        tokenProvider: editor.tokenProviderFor(widget.workspaceId, widget.path),
      ),
      wordWrap: _CodeEditorPane._selectWordWrap(context),
      indicatorBuilder:
          (context, editingController, chunkController, notifier) {
            return _LineNumberWithViewportBinder(
              controller: editingController,
              chunkController: chunkController,
              notifier: notifier,
              session: editor.documentSessionFor(
                widget.workspaceId,
                widget.path,
              ),
            );
          },
    );
    return Focus(
      // Focus observer only: claim Mod+G while the editor subtree has focus.
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: _setGotoLineClaim,
      child: codeEditor,
    );
  }
}

/// Renders the gutter (fold indicators + line numbers) and, when the file
/// has a tree-sitter [DocumentSession], keeps its viewport token requests
/// in sync with the visible line band published by re-editor's indicator
/// notifier.
///
/// Fold indicators come free: [CodeEditor] always runs the default
/// brace-based [CodeChunkController] analysis — rendering
/// [DefaultCodeChunkIndicator] is all it takes to expose collapse/expand.
/// (Brace languages only; indentation languages are not covered by the
/// re-editor default analyzer.)
class _LineNumberWithViewportBinder extends StatefulWidget {
  const _LineNumberWithViewportBinder({
    required this.controller,
    required this.chunkController,
    required this.notifier,
    required this.session,
  });

  final CodeLineEditingController controller;
  final CodeChunkController chunkController;
  final CodeIndicatorValueNotifier notifier;
  final DocumentSession? session;

  @override
  State<_LineNumberWithViewportBinder> createState() =>
      _LineNumberWithViewportBinderState();
}

class _LineNumberWithViewportBinderState
    extends State<_LineNumberWithViewportBinder> {
  EditorViewportTokenBinder? _binder;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(_LineNumberWithViewportBinder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session ||
        oldWidget.notifier != widget.notifier) {
      _bind();
    }
  }

  void _bind() {
    _binder?.dispose();
    final session = widget.session;
    _binder = session == null
        ? null
        : EditorViewportTokenBinder(
            session: session,
            notifier: widget.notifier,
          );
  }

  @override
  void dispose() {
    _binder?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DefaultCodeChunkIndicator(
          width: 14,
          controller: widget.chunkController,
          notifier: widget.notifier,
        ),
        const SizedBox(width: 2),
        DefaultCodeLineNumber(
          controller: widget.controller,
          notifier: widget.notifier,
        ),
      ],
    );
  }
}

class _FileBodyModel {
  const _FileBodyModel({
    required this.isLoading,
    required this.readOnly,
    this.loadError,
  });

  factory _FileBodyModel.from(WorkspaceEditorBucket bucket, String path) {
    return _FileBodyModel(
      isLoading: bucket.loadingPaths.contains(path),
      readOnly: bucket.readOnlyPaths.contains(path),
      loadError: bucket.errorByPath[path],
    );
  }

  final bool isLoading;
  final bool readOnly;
  final String? loadError;
}
