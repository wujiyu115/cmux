import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n_extensions.dart';

/// Absolute font-size stepper (logical px): −/+ buttons around a direct
/// numeric input. Shared by the 「界面字号」 (`uiFontSize`) and 「等宽字号」
/// (`monoFontSize`) preferences — the VS Code-style absolute px model
/// (docs/font-size-model.md §3).
///
/// [onChanged] receives an already-clamped value; the field snaps back to the
/// stored size on blur when the input is empty or unparsable.
class FontSizeSetting extends StatefulWidget {
  const FontSizeSetting({
    required this.size,
    required this.minSize,
    required this.maxSize,
    required this.onChanged,
    super.key,
  });

  final double size;
  final double minSize;
  final double maxSize;
  final ValueChanged<double> onChanged;

  @override
  State<FontSizeSetting> createState() => _FontSizeSettingState();
}

class _FontSizeSettingState extends State<FontSizeSetting> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _sizeText(widget.size));
  }

  @override
  void didUpdateWidget(covariant FontSizeSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.size != widget.size) {
      final next = _sizeText(widget.size);
      if (_controller.text != next) {
        _controller.text = next;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String _sizeText(double size) => size.round().toString();

  double get _clamped => widget.size.clamp(widget.minSize, widget.maxSize);

  void _step(double delta) {
    widget.onChanged((_clamped + delta).clamp(widget.minSize, widget.maxSize));
  }

  void _commitInput() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = _sizeText(_clamped);
      return;
    }
    widget.onChanged(parsed.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final atMin = _clamped <= widget.minSize;
    final atMax = _clamped >= widget.maxSize;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          icon: Icons.remove,
          onPressed: atMin ? null : () => _step(-1),
        ),
        // Digits-only field: the 'px' unit label sits OUTSIDE the input so it
        // can never overlap the centred digits (a suffix inside a narrow
        // centre-aligned field clipped '16' down to '1').
        SizedBox(
          width: 40,
          // Centered so the digit line box sits mid-height: the global input
          // decoration theme's height constraint top-aligns the decorator
          // content, leaving the ~18px digits visibly higher than the
          // flanking −/+/px glyphs (7px at the default scale).
          child: Center(
            child: TextField(
              controller: _controller,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(color: cs.onSurface),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                // Override the global input theme's tight 32-height
                // constraint: it top-aligns the decorator content, so the
                // digit line box rides high inside the (now natural-height)
                // field while Center pulls it to the row's midline.
                constraints: BoxConstraints(minHeight: 0),
              ),
              onSubmitted: (_) => _commitInput(),
              onEditingComplete: _commitInput,
            ),
          ),
        ),
        const SizedBox(width: 2),
        Text(l10n.fontSizePxSuffix, style: TextStyle(color: cs.onSurfaceVariant)),
        _StepButton(
          icon: Icons.add,
          onPressed: atMax ? null : () => _step(1),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
    );
  }
}
