import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_typography_scale.dart';

/// Whole-UI zoom preset strip; shows a percent field when [scaleId] is
/// `custom`. Backs the `uiZoomScale` / `uiZoomCustomMultiplier` preferences —
/// the only remaining relative knob after font sizes moved to absolute px
/// (docs/font-size-model.md).
class UiZoomSetting extends StatefulWidget {
  const UiZoomSetting({
    required this.scaleId,
    required this.customMultiplier,
    required this.onScaleIdChanged,
    required this.onCustomMultiplierChanged,
    super.key,
  });

  final String scaleId;
  final double customMultiplier;
  final ValueChanged<String> onScaleIdChanged;
  final ValueChanged<double> onCustomMultiplierChanged;

  @override
  State<UiZoomSetting> createState() => _UiZoomSettingState();
}

class _UiZoomSettingState extends State<UiZoomSetting> {
  late final TextEditingController _percentController;

  @override
  void initState() {
    super.initState();
    _percentController = TextEditingController(
      text: _percentText(widget.customMultiplier),
    );
  }

  @override
  void didUpdateWidget(covariant UiZoomSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customMultiplier != widget.customMultiplier) {
      final next = _percentText(widget.customMultiplier);
      if (_percentController.text != next) {
        _percentController.text = next;
      }
    }
  }

  @override
  void dispose() {
    _percentController.dispose();
    super.dispose();
  }

  static String _percentText(double multiplier) =>
      (multiplier * 100).round().toString();

  void _commitPercentInput() {
    final parsed = int.tryParse(_percentController.text.trim());
    if (parsed == null) {
      _percentController.text = _percentText(widget.customMultiplier);
      return;
    }
    final multiplier = clampUiZoomCustomMultiplier(parsed / 100);
    _percentController.text = _percentText(multiplier);
    widget.onCustomMultiplierChanged(multiplier);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isCustom = widget.scaleId == 'custom';

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
                value: 'compact',
                label: l10n.uiZoomCompact,
                icon: Icons.zoom_out_map,
              ),
              TpSegmentedOption<String>(
                value: 'standard',
                label: l10n.uiZoomStandard,
                icon: Icons.fit_screen_outlined,
              ),
              TpSegmentedOption<String>(
                value: 'comfortable',
                label: l10n.uiZoomComfortable,
                icon: Icons.zoom_in_map,
              ),
              TpSegmentedOption<String>(
                value: 'custom',
                label: l10n.uiZoomCustom,
                icon: Icons.tune_outlined,
              ),
            ],
            selected: widget.scaleId,
            onChanged: (id) {
              widget.onScaleIdChanged(id);
              if (id == 'custom') {
                widget.onCustomMultiplierChanged(widget.customMultiplier);
              }
            },
          ),
          if (isCustom) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 92,
              child: TextField(
                controller: _percentController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l10n.uiZoomCustomHint,
                  suffixText: '%',
                ),
                onSubmitted: (_) => _commitPercentInput(),
                onEditingComplete: _commitPercentInput,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
