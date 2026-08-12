import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_fonts.dart';

/// The mobile prototype's bottom-sheet furniture, shared by the create sheets so
/// the two cannot drift apart: grab handle, title row, field label / help, the
/// `.picker` row, and the second-level option list a picker opens.
///
/// These live here rather than in `shared_ui` because they encode one route's
/// prototype (`new-group.html` / `new-workspace.html`), not a cross-route
/// primitive — the sizes below are that prototype's, quoted per widget.

/// Prototype `--muted` (#7c7c86): a step fainter than `onSurfaceVariant`, used
/// for placeholders, counters and help text.
Color pairingMutedColor(ColorScheme cs) =>
    cs.onSurfaceVariant.withValues(alpha: 0.7);

/// Shows [child] as a prototype `.sheet`: 20px top corners, at most 78% tall,
/// lifted clear of the soft keyboard.
Future<T?> showPairingSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.78,
    ),
    builder: builder,
  );
}

/// Prototype `.grab`: 36×4 pill, 10 above / 2 below.
class PairingSheetGrab extends StatelessWidget {
  const PairingSheetGrab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: cs.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// Prototype `.sheet-head`: 17/600 title plus a 40px round close target whose
/// negative margin lets it sit in the header's own padding.
class PairingSheetHead extends StatelessWidget {
  const PairingSheetHead({super.key, required this.title, this.onClose});

  final String title;

  /// Null disables the close button — used while a submit is in flight.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Transform.translate(
            offset: const Offset(8, -8),
            child: TpIconButton(
              icon: Icons.close,
              tooltip: context.l10n.close,
              size: 40,
              iconSize: 20,
              borderRadius: 20,
              color: pairingMutedColor(cs),
              backgroundColor: Colors.transparent,
              onTap: onClose,
            ),
          ),
        ],
      ),
    );
  }
}

/// Prototype `.sheet-sub`: one muted line under the title explaining the sheet.
class PairingSheetSubtitle extends StatelessWidget {
  const PairingSheetSubtitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.5,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Prototype `.field-label`: 13/600 name, an optional `.opt` marker
/// ("required" / "optional"), and an optional right-aligned `used/max` counter.
class PairingFieldLabel extends StatelessWidget {
  const PairingFieldLabel({
    super.key,
    required this.label,
    this.marker,
    this.used,
    this.max,
  });

  final String label;
  final String? marker;
  final int? used;
  final int? max;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = pairingMutedColor(cs);
    final counterUsed = used;
    final counterMax = max;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.26,
              color: cs.onSurfaceVariant,
            ),
          ),
          if (marker != null) ...[
            const SizedBox(width: 6),
            Text(
              marker!,
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ],
          const Spacer(),
          if (counterUsed != null && counterMax != null)
            // Mono: proportional digits would shift the label as you type.
            Text(
              '$counterUsed/$counterMax',
              style: appMonoTextStyle(context, fontSize: 12.5, color: muted),
            ),
        ],
      ),
    );
  }
}

/// Prototype `.field-help`, and its `.err` variant.
class PairingFieldHelp extends StatelessWidget {
  const PairingFieldHelp(this.text, {super.key, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 7, 2, 0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.45,
          letterSpacing: 0.01,
          color: isError ? cs.error : pairingMutedColor(cs),
        ),
      ),
    );
  }
}

/// Prototype `.field-input`: 14px radius, 15/16 padding, 17px text, an accent
/// border plus a 3px accent halo while focused, danger border when invalid.
///
/// Needs [focusNode] from the caller (and a rebuild on its changes) because the
/// halo is drawn outside the border, where no `InputBorder` can reach.
class PairingSheetTextField extends StatelessWidget {
  const PairingSheetTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    this.enabled = true,
    this.invalid = false,
    this.autofocus = false,
    this.maxLength,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final bool enabled;
  final bool invalid;
  final bool autofocus;
  final int? maxLength;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final focused = focusNode.hasFocus;
    final borderColor = invalid
        ? cs.error
        : focused
        ? cs.primary
        : cs.outlineVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: focused && !invalid
            ? [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.16),
                  spreadRadius: 3,
                ),
              ]
            : const [],
      ),
      child: TpInput(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        autofocus: autofocus,
        maxLength: maxLength,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        textInputAction: TextInputAction.done,
        onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
        style: const TextStyle(fontSize: 17),
        decoration: InputDecoration(
          hintText: hintText,
          // The field label carries the counter; the built-in one would repeat
          // it under the box and add a row of height.
          counterText: '',
          filled: true,
          fillColor: cs.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          border: _border(borderColor),
          enabledBorder: _border(borderColor),
          focusedBorder: _border(borderColor),
          errorBorder: _border(cs.error),
          focusedErrorBorder: _border(cs.error),
        ),
      ),
    );
  }

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: color),
  );
}

/// Prototype's in-button loading state: an 18px spinner ahead of "creating…".
class PairingCreatingLabel extends StatelessWidget {
  const PairingCreatingLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    // Inherits the button's own foreground, so it reads on both the filled and
    // the outlined variant.
    final color = DefaultTextStyle.of(context).style.color;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: color),
        ),
        const SizedBox(width: 9),
        Text(label),
      ],
    );
  }
}

/// Prototype `.picker`: a bordered row showing the current value, tapped to open
/// a second-level option sheet. 52 tall, 14px radius, 17px value.
class PairingPickerRow extends StatelessWidget {
  const PairingPickerRow({
    super.key,
    required this.icon,
    required this.value,
    required this.onTap,
    this.isPlaceholder = false,
  });

  final IconData icon;
  final String value;
  final VoidCallback? onTap;
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = pairingMutedColor(cs);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  color: isPlaceholder ? muted : cs.onSurface,
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, size: 20, color: muted),
          ],
        ),
      ),
    );
  }
}

/// One option in [showPairingOptionSheet]. [mono] renders [label] in the
/// monospace face, for values that are paths rather than prose.
class PairingSheetOption<T> {
  const PairingSheetOption({
    required this.value,
    required this.label,
    this.mono = false,
  });

  final T value;
  final String label;
  final bool mono;
}

/// Prototype's second-level sheet (`.sheet.lv2` + `.sheet-list`): the same sheet
/// chrome over a checkable list. Returns the chosen value, or null if dismissed.
///
/// A sheet rather than a dropdown because it is what the prototype specifies,
/// and because a 52px row is a far easier target on a phone than a menu item.
Future<T?> showPairingOptionSheet<T>({
  required BuildContext context,
  required String title,
  required List<PairingSheetOption<T>> options,
  required T? current,
}) {
  return showPairingSheet<T>(
    context: context,
    builder: (sheetContext) {
      final cs = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PairingSheetGrab(),
            PairingSheetHead(
              title: title,
              onClose: () => Navigator.of(sheetContext).pop(),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 18),
                children: [
                  for (final option in options)
                    _OptionRow<T>(
                      option: option,
                      selected: option.value == current,
                      onTap: () =>
                          Navigator.of(sheetContext).pop(option.value),
                      accent: cs.primary,
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Prototype `.sheet-opt`: 52 tall, 18px label, accent tick on the current one.
class _OptionRow<T> extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.selected,
    required this.onTap,
    required this.accent,
  });

  final PairingSheetOption<T> option;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: option.mono
                    ? appMonoTextStyle(
                        context,
                        fontSize: 15,
                        color: selected ? accent : cs.onSurface,
                      )
                    : TextStyle(
                        fontSize: 18,
                        color: selected ? accent : cs.onSurface,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Space is reserved whether or not the tick shows, so selecting a
            // row cannot reflow the list.
            SizedBox(
              width: 22,
              height: 22,
              child: selected
                  ? Icon(Icons.check, size: 22, color: accent)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
