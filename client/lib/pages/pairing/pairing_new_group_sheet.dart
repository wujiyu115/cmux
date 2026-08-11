import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';

/// Bottom sheet to create a workspace group on the paired desktop. Mirrors
/// [showPairingManualEntrySheet]'s layout (keyboard-lifted, single field +
/// primary/ghost actions).
///
/// [cubit] must be captured by the caller *before* opening the sheet: the modal
/// route sits above the pairing shell's `BlocProvider`, so `context.read` inside
/// the sheet would not find it.
Future<void> showPairingNewGroupSheet(
  BuildContext context,
  PairingClientCubit cubit,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PairingNewGroupSheet(cubit: cubit),
  );
}

class _PairingNewGroupSheet extends StatefulWidget {
  const _PairingNewGroupSheet({required this.cubit});

  final PairingClientCubit cubit;

  @override
  State<_PairingNewGroupSheet> createState() => _PairingNewGroupSheetState();
}

class _PairingNewGroupSheetState extends State<_PairingNewGroupSheet> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await widget.cubit.createGroup(name);
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _submitting = false;
        // Localized headline plus the host's own words. The tail is not
        // translatable (it is an exception / RPC error) and it is the only thing
        // that distinguishes a stale desktop — `unknown method: group.create` —
        // from a real failure.
        _error = '${context.l10n.pairingGroupCreateFailed}\n${result.error}';
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final spacing = context.tpSpacing;
    final error = _error;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.lg,
            spacing.lg,
            spacing.lg,
            spacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.pairingNewGroup, style: styles.lgSemibold),
              SizedBox(height: spacing.md),
              TpInput(
                controller: _controller,
                autofocus: true,
                enabled: !_submitting,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: l10n.pairingNewGroupNameHint,
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              if (error != null) ...[
                SizedBox(height: spacing.sm),
                Text(error, style: styles.smColored(cs.error)),
              ],
              SizedBox(height: spacing.md),
              TpButton(
                onPressed: _submitting ? null : _submit,
                child: Text(l10n.pairingCreate),
              ),
              SizedBox(height: spacing.xs),
              TpButton(
                variant: TpButtonVariant.ghost,
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
