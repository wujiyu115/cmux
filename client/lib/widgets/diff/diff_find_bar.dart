import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../workbench/code_find_panel.dart';

/// [CodeEditor.findBuilder] wrapper for the diff views.
///
/// The diff renderers align their line bands, gutter, ribbon, and overview
/// ruler to re-editor's default 5px content top padding. [CodeEditor] shifts
/// content down by `find.preferredSize.height` when a find bar is attached, so
/// this builder reports a zero-height preferred size and paints the
/// [CodeFindPanel] as a pure top-right overlay instead — the alignment stays
/// pixel-exact whether or not the find panel is open.
///
/// The panel itself renders nothing while the controller is closed.
class DiffFindBar extends StatelessWidget implements PreferredSizeWidget {
  const DiffFindBar({required this.controller, super.key});

  final CodeFindController controller;

  @override
  Size get preferredSize => Size.zero;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topRight,
      child: CodeFindPanel(
        controller: controller,
        // Diff editors are read-only: hide the replace row.
        readOnly: true,
      ),
    );
  }
}
