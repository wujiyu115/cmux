import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../theme/terminal/terminal_color_slots.dart';

/// Grid of the 24 override slots. Each field shows the slot label, a swatch of
/// the *effective* value, and a `#RRGGBB` / `#AARRGGBB` hex field. Invalid input
/// shows an inline error and does not write. Enabled only when custom colours
/// are on.
class TerminalColorSlotEditor extends StatelessWidget {
  const TerminalColorSlotEditor({
    required this.enabled,
    required this.baseSlotValues,
    required this.overrides,
    required this.onSetOverride,
    required this.onClearOverride,
    required this.onResetAll,
    super.key,
  });

  final bool enabled;

  /// Scheme (pre-override) ARGB value per slot, from `terminalThemeSlotValues`.
  final Map<String, int> baseSlotValues;
  final Map<String, int> overrides;
  final void Function(String slot, int argb) onSetOverride;
  final void Function(String slot) onClearOverride;
  final VoidCallback onResetAll;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(l10n.terminalCustomColorsSectionTitle),
              ),
              TpButton(
                variant: TpButtonVariant.ghost,
                onPressed: enabled && overrides.isNotEmpty ? onResetAll : null,
                child: Text(l10n.terminalColorResetAll),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              for (final slot in kTerminalColorSlots)
                SizedBox(
                  width: 220,
                  child: _SlotField(
                    key: ValueKey(slot),
                    slot: slot,
                    enabled: enabled,
                    effectiveValue:
                        overrides[slot] ?? baseSlotValues[slot] ?? 0xFF000000,
                    hasOverride: overrides.containsKey(slot),
                    onSet: (argb) => onSetOverride(slot, argb),
                    onClear: () => onClearOverride(slot),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SlotField extends StatefulWidget {
  const _SlotField({
    required this.slot,
    required this.enabled,
    required this.effectiveValue,
    required this.hasOverride,
    required this.onSet,
    required this.onClear,
    super.key,
  });

  final String slot;
  final bool enabled;
  final int effectiveValue;
  final bool hasOverride;
  final ValueChanged<int> onSet;
  final VoidCallback onClear;

  @override
  State<_SlotField> createState() => _SlotFieldState();
}

class _SlotFieldState extends State<_SlotField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: formatTerminalHexColor(widget.effectiveValue),
    );
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _SlotField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reflect external changes (reset, scheme switch) only while not editing,
    // so we never clobber in-progress typing.
    if (!_focusNode.hasFocus &&
        widget.effectiveValue != oldWidget.effectiveValue) {
      final next = formatTerminalHexColor(widget.effectiveValue);
      if (_controller.text != next) {
        _controller.text = next;
        _invalid = false;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      // Empty clears the override (falls back to the scheme colour).
      if (_invalid) setState(() => _invalid = false);
      if (widget.hasOverride) widget.onClear();
      return;
    }
    final parsed = parseTerminalHexColor(trimmed);
    if (parsed == null) {
      if (!_invalid) setState(() => _invalid = true);
      return;
    }
    if (_invalid) setState(() => _invalid = false);
    widget.onSet(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final swatchColor = Color(0xFF000000 | (widget.effectiveValue & 0xFFFFFF));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.terminalColorSlotLabel(widget.slot),
                style: styles.mutedSm,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.enabled && widget.hasOverride)
              TpIconButton(
                icon: Icons.refresh,
                compact: true,
                size: 24,
                tooltip: l10n.terminalColorResetSlot,
                onTap: widget.onClear,
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: swatchColor,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: cs.outlineVariant),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TpInput(
                controller: _controller,
                focusNode: _focusNode,
                enabled: widget.enabled,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  isDense: true,
                  errorText: _invalid ? l10n.terminalColorInvalidHex : null,
                  errorStyle: styles.mutedSm.copyWith(color: cs.error),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
