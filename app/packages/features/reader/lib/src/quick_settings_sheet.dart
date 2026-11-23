import 'package:core/domain_lookup.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Bottom sheet with the quick text settings: size, spacing and dimming.
///
/// Reads the current preferences from [display] and reports every change
/// through [onChanged]; the owner updates [display] and saves with a delay.
class QuickSettingsSheet extends StatelessWidget {
  /// Creates the sheet.
  const new({required this.display, required this.onChanged, super.key});

  /// Current preferences; the sheet rebuilds when they change.
  final ValueListenable<DisplayPrefs> display;

  /// Called with the changed preferences.
  final ValueChanged<DisplayPrefs> onChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ValueListenableBuilder<DisplayPrefs>(
        valueListenable: display,
        builder: (context, prefs, _) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Font size')),
                  OutlinedButton(
                    onPressed: prefs.fontSize <= DisplayPrefs.minFontSize
                        ? null
                        : () => onChanged(
                            prefs.copyWith(fontSize: prefs.fontSize - 1),
                          ),
                    child: const Text('A−'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(prefs.fontSize.round().toString()),
                  ),
                  OutlinedButton(
                    onPressed: prefs.fontSize >= DisplayPrefs.maxFontSize
                        ? null
                        : () => onChanged(
                            prefs.copyWith(fontSize: prefs.fontSize + 1),
                          ),
                    child: const Text('A+'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Line spacing'),
              Slider(
                key: const Key('line-height'),
                min: 1,
                max: 2.5,
                divisions: 15,
                value: prefs.lineHeight.clamp(1, 2.5),
                label: prefs.lineHeight.toStringAsFixed(1),
                onChanged: (v) => onChanged(
                  prefs.copyWith(lineHeight: (v * 10).round() / 10),
                ),
              ),
              const Text('Dimming'),
              Slider(
                key: const Key('dim'),
                max: DisplayPrefs.maxDim,
                divisions: 16,
                value: prefs.dim.clamp(0, DisplayPrefs.maxDim),
                label: prefs.dim.toStringAsFixed(2),
                onChanged: (v) =>
                    onChanged(prefs.copyWith(dim: (v * 20).round() / 20)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
