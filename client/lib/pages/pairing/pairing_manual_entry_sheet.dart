import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/pairing/pairing_offer.dart';
import '../../theme/app_fonts.dart';
import '../../theme/app_typography_scale.dart';
import '../../utils/ui/app_keys.dart';
import 'pairing_block_button.dart';

/// Manual pairing-code entry, as a bottom sheet rather than a dialog: the field
/// is a long mono payload and the keyboard covers half the screen, so anchoring
/// to the bottom edge keeps the input and its primary action adjacent.
///
/// Returns the parsed [PairingOffer], or null when dismissed.
Future<PairingOffer?> showPairingManualEntrySheet(BuildContext context) {
  return showModalBottomSheet<PairingOffer>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _PairingManualEntrySheet(),
  );
}

class _PairingManualEntrySheet extends StatefulWidget {
  const _PairingManualEntrySheet();

  @override
  State<_PairingManualEntrySheet> createState() =>
      _PairingManualEntrySheetState();
}

class _PairingManualEntrySheetState extends State<_PairingManualEntrySheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final offer = PairingOffer.tryParse(_controller.text);
    if (offer == null) {
      setState(() => _error = context.l10n.pairingInvalidCode);
      return;
    }
    Navigator.of(context).pop(offer);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final spacing = context.tpSpacing;
    final typography = context.appTypography;
    final error = _error;

    return Padding(
      key: AppKeys.pairingManualEntrySheet,
      // Lifts the sheet above the soft keyboard instead of letting it cover the
      // field and the Pair button.
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
              Text(l10n.pairingEnterPairingCode, style: styles.lgSemibold),
              SizedBox(height: spacing.sm),
              Text(l10n.pairingCodeTtlHint, style: styles.mutedSm),
              SizedBox(height: spacing.md),
              TpTextarea(
                key: AppKeys.pairingManualEntryField,
                controller: _controller,
                autofocus: true,
                minHeight: 92,
                resizable: false,
                style: appMonoTextStyle(context, fontSize: typography.bodyLarge),
                decoration: InputDecoration(hintText: l10n.pairingCodeHint),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              if (error != null) ...[
                SizedBox(height: spacing.sm),
                Text(error, style: styles.smColored(cs.error)),
              ],
              SizedBox(height: spacing.md),
              PairingBlockButton(
                onPressed: _submit,
                child: Text(l10n.pairingPair),
              ),
              SizedBox(height: spacing.xs),
              PairingBlockButton(
                variant: PairingButtonVariant.quiet,
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
