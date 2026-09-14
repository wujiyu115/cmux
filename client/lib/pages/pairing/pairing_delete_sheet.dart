import 'package:flutter/material.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/pairing/pairing_client.dart';
import '../../utils/ui/app_keys.dart';
import 'pairing_block_button.dart';
import 'pairing_sheet_parts.dart';

/// Confirmation sheet for deleting a workspace from the phone.
///
/// [cubit] is captured by the caller *before* the sheet opens for the same
/// reason as the create sheets: the modal route sits above the pairing shell's
/// `BlocProvider`, so `context.read` inside would not find it.
Future<void> showPairingDeleteWorkspaceSheet(
  BuildContext context,
  PairingClientCubit cubit,
  PairingWorkspaceNode workspace,
) {
  final l10n = context.l10n;
  return showPairingSheet<void>(
    context: context,
    builder: (_) => _PairingDeleteSheet(
      cubit: cubit,
      title: l10n.deleteWorkspace,
      message: l10n.pairingDeleteWorkspaceMessage(
        workspace.title.isEmpty ? workspace.workspaceId : workspace.title,
      ),
      confirmLabel: l10n.delete,
      submit: () => cubit.deleteWorkspace(workspace.workspaceId),
    ),
  );
}

/// Confirmation sheet for closing one terminal pane from the phone.
Future<void> showPairingCloseTerminalSheet(
  BuildContext context,
  PairingClientCubit cubit,
  PairingSessionNode node,
) {
  final l10n = context.l10n;
  return showPairingSheet<void>(
    context: context,
    builder: (_) => _PairingDeleteSheet(
      cubit: cubit,
      title: l10n.pairingCloseTerminal,
      message: l10n.pairingCloseTerminalMessage(
        node.title.isEmpty ? node.nodeKey : node.title,
      ),
      confirmLabel: l10n.closeTab,
      submit: () => cubit.closeTerminal(node.paneId ?? node.nodeKey),
    ),
  );
}

class _PairingDeleteSheet extends StatefulWidget {
  const _PairingDeleteSheet({
    required this.cubit,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.submit,
  });

  final PairingClientCubit cubit;
  final String title;
  final String message;

  /// The confirm button's label — "delete" for a workspace, "close" for a pane.
  final String confirmLabel;

  /// The host-side request, already bound to its target id.
  final Future<PairingCallResult<void>> Function() submit;

  @override
  State<_PairingDeleteSheet> createState() => _PairingDeleteSheetState();
}

class _PairingDeleteSheetState extends State<_PairingDeleteSheet> {
  bool _submitting = false;

  /// The host's own refusal text, shown after the localized headline — a
  /// desktop predating these RPCs answers `unknown method: workspace.delete`,
  /// which is the one fact identifying a stale desktop.
  String? _error;

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await widget.submit();
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _submitting = false;
        _error = result.error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hostError = _error;
    return SafeArea(
      top: false,
      child: Column(
        key: AppKeys.pairingDeleteSheet,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PairingSheetGrab(),
          PairingSheetHead(
            title: widget.title,
            onClose: _submitting ? null : () => Navigator.of(context).pop(),
          ),
          PairingSheetSubtitle(widget.message),
          if (hostError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: PairingFieldHelp(
                '${l10n.pairingDeleteFailed} $hostError',
                isError: true,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PairingBlockButton(
                  key: AppKeys.pairingDeleteConfirmButton,
                  destructive: true,
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? PairingCreatingLabel(label: l10n.pairingDeleting)
                      : Text(widget.confirmLabel),
                ),
                const SizedBox(height: 10),
                PairingBlockButton(
                  variant: PairingButtonVariant.quiet,
                  onPressed:
                      _submitting ? null : () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
