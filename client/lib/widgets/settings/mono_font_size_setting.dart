import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_typography_scale.dart';

/// Monospace size strip (small / default / large / custom %) for the
/// `monoFontScale` preference shared by terminal, editor, and diffs.
class MonoFontSizeSetting extends StatefulWidget {
  const MonoFontSizeSetting({
    required this.scale,
    required this.onChanged,
    super.key,
  });

  final double scale;
  final ValueChanged<double> onChanged;

  @override
  State<MonoFontSizeSetting> createState() => _MonoFontSizeSettingState();
}

class _MonoFontSizeSettingState extends State<MonoFontSizeSetting> {
  late final TextEditingController _percentController;

  /// True after the user taps 自定义 — keeps the segment + % field visible
  /// until a preset is picked (or an external pref change lands on a preset).
  bool _customPicked = false;

  @override
  void initState() {
    super.initState();
    _percentController = TextEditingController(
      text: _percentText(widget.scale),
    );
  }

  @override
  void didUpdateWidget(covariant MonoFontSizeSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scale != widget.scale) {
      final next = _percentText(widget.scale);
      if (_percentController.text != next) {
        _percentController.text = next;
      }
      if (_isPreset(widget.scale)) _customPicked = false;
    }
  }

  @override
  void dispose() {
    _percentController.dispose();
    super.dispose();
  }

  static String _percentText(double scale) => (scale * 100).round().toString();

  static bool _isPreset(double scale) =>
      scale == kMonoFontScaleSmall ||
      scale == kDefaultMonoFontScale ||
      scale == kMonoFontScaleLarge;

  String get _segmentId {
    if (!_customPicked) {
      if (widget.scale == kMonoFontScaleSmall) return 'small';
      if (widget.scale == kDefaultMonoFontScale) return 'standard';
      if (widget.scale == kMonoFontScaleLarge) return 'large';
    }
    return 'custom';
  }

  void _commitPercentInput() {
    final parsed = int.tryParse(_percentController.text.trim());
    if (parsed == null) {
      _percentController.text = _percentText(widget.scale);
      return;
    }
    final scale = clampMonoFontScale(parsed / 100);
    _percentController.text = _percentText(scale);
    widget.onChanged(scale);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isCustom = _segmentId == 'custom';

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TpSegmentedPicker<String>(
            segments: [
              TpSegmentedOption<String>(
                value: 'small',
                label: l10n.monoFontSizeSmall,
                icon: Icons.density_small_outlined,
              ),
              TpSegmentedOption<String>(
                value: 'standard',
                label: l10n.monoFontSizeStandard,
                icon: Icons.density_medium_outlined,
              ),
              TpSegmentedOption<String>(
                value: 'large',
                label: l10n.monoFontSizeLarge,
                icon: Icons.density_large_outlined,
              ),
              TpSegmentedOption<String>(
                value: 'custom',
                label: l10n.monoFontSizeCustom,
                icon: Icons.tune_outlined,
              ),
            ],
            selected: _segmentId,
            onChanged: (id) => switch (id) {
              'small' => widget.onChanged(kMonoFontScaleSmall),
              'standard' => widget.onChanged(kDefaultMonoFontScale),
              'large' => widget.onChanged(kMonoFontScaleLarge),
              _ => setState(() => _customPicked = true),
            },
          ),
          if (isCustom) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
              height: 38,
              child: TextField(
                controller: _percentController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l10n.monoFontSizeCustomHint,
                  suffixText: '%',
                ),
                onSubmitted: (_) => _commitPercentInput(),
                onEditingComplete: _commitPercentInput,
                onTapOutside: (_) => _commitPercentInput(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
