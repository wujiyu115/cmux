import 'package:flutter/material.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/pairing/pairing_client.dart';
import 'pairing_block_button.dart';
import 'pairing_sheet_parts.dart';

/// Bottom sheet to create a workspace group on the paired desktop.
///
/// Follows the mobile prototype's `new-group.html`: grab handle, title row with a
/// close button, one labelled field carrying a live character counter and a help
/// line that turns into the error, then stacked primary/ghost actions.
///
/// Its *copy* deliberately does not follow that prototype, which describes groups
/// as phone-local and never synced. This app creates them through the desktop's
/// own group index, so they show up in the desktop sidebar immediately — saying
/// otherwise would be a lie in the one place the user looks for reassurance.
///
/// [cubit] and [groups] must be captured by the caller *before* the sheet opens:
/// the modal route sits above the pairing shell's `BlocProvider`, so
/// `context.read` inside the sheet would not find it. [groups] is what makes the
/// duplicate-name check possible without a round trip.
Future<void> showPairingNewGroupSheet(
  BuildContext context,
  PairingClientCubit cubit,
  List<PairingGroup> groups,
) {
  return showPairingSheet<void>(
    context: context,
    builder: (_) => _PairingNewGroupSheet(cubit: cubit, groups: groups),
  );
}

class _PairingNewGroupSheet extends StatefulWidget {
  const _PairingNewGroupSheet({required this.cubit, required this.groups});

  final PairingClientCubit cubit;
  final List<PairingGroup> groups;

  @override
  State<_PairingNewGroupSheet> createState() => _PairingNewGroupSheetState();
}

/// Prototype `#gname`: `maxlength="24"`, surfaced as the label's counter.
const _nameMaxLength = 24;

class _PairingNewGroupSheetState extends State<_PairingNewGroupSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _submitting = false;

  /// The host's own refusal text, shown after the localized headline. Distinct
  /// from [_isDuplicate], which is caught here before anything is sent.
  String? _error;

  @override
  void initState() {
    super.initState();
    // Both drive the build: the text feeds the counter, the duplicate check and
    // the create button's enabled state; focus draws the input's accent ring.
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() => _error = null);

  void _onFocusChanged() => setState(() {});

  String get _name => _controller.text.trim();

  /// Case-insensitive, as in the prototype: two groups differing only in case
  /// would be indistinguishable in the list.
  bool get _isDuplicate =>
      _name.isNotEmpty &&
      widget.groups.any(
        (group) => group.name.trim().toLowerCase() == _name.toLowerCase(),
      );

  bool get _canSubmit => _name.isNotEmpty && !_isDuplicate && !_submitting;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await widget.cubit.createGroup(_name);
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
    final duplicate = _isDuplicate;
    final hostError = _error;

    return Padding(
      // Lifts the sheet above the soft keyboard instead of letting it cover the
      // field. Not in the prototype, which is a static mock.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PairingSheetGrab(),
            PairingSheetHead(
              title: l10n.pairingNewGroup,
              onClose:
                  _submitting ? null : () => Navigator.of(context).pop(),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PairingFieldLabel(
                      label: l10n.pairingNewGroupNameLabel,
                      // Counts what the field will accept, which is characters
                      // rather than code units — a CJK group name is 1 per glyph.
                      used: _controller.text.characters.length,
                      max: _nameMaxLength,
                    ),
                    PairingSheetTextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      hintText: l10n.pairingNewGroupNameHint,
                      enabled: !_submitting,
                      invalid: duplicate || hostError != null,
                      autofocus: true,
                      maxLength: _nameMaxLength,
                      onSubmitted: _submit,
                    ),
                    // One line that carries three states: guidance, the local
                    // duplicate check, and the host's refusal. The host's words
                    // ride after the headline — they are untranslatable, and the
                    // only thing that tells a stale desktop from a real failure.
                    PairingFieldHelp(
                      switch ((duplicate, hostError)) {
                        (true, _) => l10n.pairingNewGroupDuplicate,
                        (_, final String error) =>
                          '${l10n.pairingGroupCreateFailed} $error',
                        _ => l10n.pairingNewGroupHelp,
                      },
                      isError: duplicate || hostError != null,
                    ),
                  ],
                ),
              ),
            ),
            // Prototype `.sheet-actions` (20/20/2) plus the sheet's own 18px
            // bottom padding, folded into one inset.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PairingBlockButton(
                    onPressed: _canSubmit ? _submit : null,
                    child: _submitting
                        ? PairingCreatingLabel(label: l10n.pairingCreating)
                        : Text(l10n.pairingCreate),
                  ),
                  const SizedBox(height: 10),
                  PairingBlockButton(
                    outlined: true,
                    onPressed:
                        _submitting ? null : () => Navigator.of(context).pop(),
                    child: Text(l10n.cancel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
