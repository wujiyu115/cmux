import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        SizedBox(
          width: 64,
          child: TextField(
            controller: _controller,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              suffixText: 'px',
              suffixStyle: TextStyle(color: cs.onSurfaceVariant),
            ),
            onSubmitted: (_) => _commitInput(),
            onEditingComplete: _commitInput,
          ),
        ),
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
