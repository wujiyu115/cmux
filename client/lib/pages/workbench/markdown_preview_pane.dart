import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:re_editor/re_editor.dart';

import '../../cubits/editor_cubit.dart';
import '../../services/editor/markdown_preview_link_handler.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import '../../theme/app_markdown_style_sheet.dart';

/// Markdown preview pane for one open file.
///
/// Owns an external scroll controller seeded from [EditorCubit]'s retained
/// anchor and writes every pixel change back, so the viewport offset survives
/// tab de-selection and remount (same contract as the code editor pane).
class MarkdownPreviewPane extends StatefulWidget {
  const MarkdownPreviewPane({
    required this.workspaceId,
    required this.path,
    required this.controller,
    super.key,
  });

  final String workspaceId;
  final String path;
  final CodeLineEditingController controller;

  @override
  State<MarkdownPreviewPane> createState() => _MarkdownPreviewPaneState();
}

class _MarkdownPreviewPaneState extends State<MarkdownPreviewPane> {
  late String _data = widget.controller.text;
  late final EditorCubit _editor;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _editor = context.read<EditorCubit>();
    _scrollController = ScrollController(
      initialScrollOffset: _editor.markdownPreviewScrollOffsetFor(
        widget.workspaceId,
        widget.path,
      ),
    );
    _scrollController.addListener(_persistScroll);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(MarkdownPreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _data = widget.controller.text;
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _scrollController.removeListener(_persistScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _persistScroll() {
    if (!_scrollController.hasClients) return;
    _editor.setMarkdownPreviewScrollOffset(
      widget.workspaceId,
      widget.path,
      _scrollController.position.pixels,
    );
  }

  void _onControllerChanged() {
    final next = widget.controller.text;
    // Ignore selection-only controller notifies — rebuilding MarkdownBody /
    // SelectionArea mid-drag jumps the scroll back toward the document head.
    if (next == _data) return;
    setState(() => _data = next);
  }

  @override
  Widget build(BuildContext context) {
    final opener = context.read<WorkbenchEditorOpener>();
    final roots = WorkspaceToolsScope.maybeOf(context)?.roots ?? const [];
    // SelectionArea must sit *inside* the scroll content. As an ancestor it
    // enables edge auto-scroll while selecting, which yanks long previews to
    // the top (flutter/flutter#110917).
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: SelectionArea(
        child: MarkdownBody(
          data: _data,
          styleSheet: buildAppMarkdownStyleSheet(Theme.of(context)),
          selectable: false,
          onTapLink: (text, href, title) {
            unawaited(
              handleMarkdownPreviewLink(
                href: href,
                markdownFilePath: widget.path,
                workspaceId: widget.workspaceId,
                workspaceRoots: roots,
                opener: opener,
              ),
            );
          },
        ),
      ),
    );
  }
}
