import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/terminal/terminal_layout_presets.dart';

/// Compact split / layout toolbar rendered directly above a [TerminalSplitView].
///
/// Modelled on the cmux toolbar row under the tab strip: split right / split
/// down, a layout-preset popup, equalize, a zoom toggle, and close pane. It is
/// pure UI — every action is a plain callback wired by the hosting panel; it
/// holds no cubit or group reference.
class TerminalLayoutToolbar extends StatelessWidget {
  const TerminalLayoutToolbar({
    required this.onSplitRight,
    required this.onSplitDown,
    required this.onApplyPreset,
    required this.onEqualize,
    required this.onToggleZoom,
    required this.onShowCommandLog,
    this.onShowAgentSessions,
    this.isZoomed = false,
    super.key,
  });

  final VoidCallback onSplitRight;
  final VoidCallback onSplitDown;
  final ValueChanged<TerminalLayoutPreset> onApplyPreset;
  final VoidCallback onEqualize;
  final VoidCallback onToggleZoom;

  /// Opens the command log window (the cmux "list" toolbar button).
  final VoidCallback onShowCommandLog;

  /// Opens the resumable agent-CLI sessions menu anchored at the button.
  /// Null hides the button (e.g. tests and harnesses without the service).
  final void Function(Offset globalPosition)? onShowAgentSessions;

  /// Whether the active surface currently has a zoomed pane (drives the icon).
  final bool isZoomed;

  static const double kToolbarHeight = 32;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      height: kToolbarHeight,
      child: Row(
        children: [
          const SizedBox(width: 4),
          TpIconButton(
            icon: Icons.border_vertical,
            compact: true,
            size: TpIconButton.kCompactSize,
            tooltip: l10n.workspaceTerminalSplitRight,
            onTap: onSplitRight,
          ),
          TpIconButton(
            icon: Icons.border_horizontal,
            compact: true,
            size: TpIconButton.kCompactSize,
            tooltip: l10n.workspaceTerminalSplitDown,
            onTap: onSplitDown,
          ),
          _divider(),
          _PresetMenuButton(onApplyPreset: onApplyPreset),
          TpIconButton(
            icon: Icons.balance,
            compact: true,
            size: TpIconButton.kCompactSize,
            tooltip: l10n.workspaceTerminalEqualize,
            onTap: onEqualize,
          ),
          TpIconButton(
            icon: isZoomed ? Icons.zoom_in_map : Icons.zoom_out_map,
            compact: true,
            size: TpIconButton.kCompactSize,
            tooltip: isZoomed
                ? l10n.workspaceTerminalUnzoomPane
                : l10n.workspaceTerminalZoomPane,
            onTap: onToggleZoom,
          ),
          _divider(),
          TpIconButton(
            icon: Icons.list_alt,
            compact: true,
            size: TpIconButton.kCompactSize,
            tooltip: l10n.workspaceTerminalCommandLog,
            onTap: onShowCommandLog,
          ),
          if (onShowAgentSessions != null)
            _AgentSessionsMenuButton(onShow: onShowAgentSessions!),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _divider() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: TpSeparator(axis: Axis.vertical),
      );
}

/// Agent-CLI sessions button: hands its anchor position (bottom-left of the
/// button) to [onShow], which opens the resumable-sessions menu there.
class _AgentSessionsMenuButton extends StatelessWidget {
  const _AgentSessionsMenuButton({required this.onShow});

  final void Function(Offset globalPosition) onShow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Builder(
      builder: (buttonContext) {
        return TpIconButton(
          icon: Icons.history,
          compact: true,
          size: TpIconButton.kCompactSize,
          tooltip: l10n.workspaceTerminalResumeSessions,
          onTap: () {
            final box = buttonContext.findRenderObject() as RenderBox?;
            if (box == null) return;
            onShow(box.localToGlobal(box.size.bottomLeft(Offset.zero)));
          },
        );
      },
    );
  }
}

/// Layout-preset popup: opens a [TpActionMenu] anchored at the button and
/// forwards the chosen [TerminalLayoutPreset].
class _PresetMenuButton extends StatelessWidget {
  const _PresetMenuButton({required this.onApplyPreset});

  final ValueChanged<TerminalLayoutPreset> onApplyPreset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Builder(
      builder: (buttonContext) {
        return TpIconButton(
          icon: Icons.grid_view,
          compact: true,
          size: TpIconButton.kCompactSize,
          tooltip: l10n.workspaceTerminalLayout,
          onTap: () => _open(buttonContext),
        );
      },
    );
  }

  Future<void> _open(BuildContext buttonContext) async {
    final l10n = buttonContext.l10n;
    final box = buttonContext.findRenderObject() as RenderBox?;
    if (box == null) return;
    final position = box.localToGlobal(box.size.bottomLeft(Offset.zero));
    final specs = <TpActionMenuSpec>[
      TpActionMenuSpec.item(
        value: TerminalLayoutPreset.single,
        icon: Icons.crop_square,
        label: l10n.workspaceTerminalLayoutSingle,
      ),
      TpActionMenuSpec.item(
        value: TerminalLayoutPreset.columns2,
        icon: Icons.view_column,
        label: l10n.workspaceTerminalLayoutColumns2,
      ),
      TpActionMenuSpec.item(
        value: TerminalLayoutPreset.columns3,
        icon: Icons.view_week,
        label: l10n.workspaceTerminalLayoutColumns3,
      ),
      TpActionMenuSpec.item(
        value: TerminalLayoutPreset.grid2x2,
        icon: Icons.grid_view,
        label: l10n.workspaceTerminalLayoutGrid,
      ),
      TpActionMenuSpec.item(
        value: TerminalLayoutPreset.mainStack,
        icon: Icons.view_quilt,
        label: l10n.workspaceTerminalLayoutMainStack,
      ),
    ];
    final selected = await showTpActionMenuFromSpecs<TerminalLayoutPreset>(
      context: buttonContext,
      globalPosition: position,
      specs: specs,
    );
    if (selected != null) onApplyPreset(selected);
  }
}
