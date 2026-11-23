import 'dart:async';
import 'dart:math' as math;

import 'package:core/domain_lookup.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

final Logger _log = Logger('ReadingSection');

/// Smallest contrast ratio that is not warned about (WCAG AA, body text).
const double minContrast = 4.5;

/// Ready text/background pairs of the day mode, as `(text, background)`.
const List<(int, int)> dayPresets = [
  (0xFF212121, 0xFFFFFFFF),
  (0xFF212121, 0xFFFFFBF5),
  (0xFF3B2F2F, 0xFFF4ECD8),
  (0xFF212121, 0xFFE8E8E8),
  (0xFF212121, 0xFFE6F0E6),
  (0xFF212121, 0xFFE4ECF4),
];

/// Ready text/background pairs of the night mode, as `(text, background)`.
const List<(int, int)> nightPresets = [
  (0xFFE0E0E0, 0xFF000000),
  (0xFFE0E0E0, 0xFF121212),
  (0xFFE0E0E0, 0xFF1E1E1E),
  (0xFFC8B89A, 0xFF2B2419),
  (0xFFE0E0E0, 0xFF14181F),
  (0xFFE0E0E0, 0xFF16201A),
];

/// Relative luminance of an ARGB colour by WCAG 2.x; alpha is ignored.
double relativeLuminance(int argb) {
  double channel(int shift) {
    final c = ((argb >> shift) & 0xFF) / 255;
    return c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4) as double;
  }

  return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0);
}

/// WCAG contrast ratio of two colours, from 1 to 21.
double contrastRatio(int a, int b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Parses `RRGGBB` (a leading `#` is allowed) to an opaque ARGB colour, or
/// returns `null` if [text] is not exactly six hex digits.
int? parseHexColor(String text) {
  final match = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(text.trim());
  if (match == null) return null;
  return 0xFF000000 | int.parse(match.group(1)!, radix: 16);
}

/// The colour as six upper-case hex digits.
String formatHexColor(int argb) =>
    (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

Future<void> _updateDisplay(
  WidgetRef ref,
  DisplayPrefs Function(DisplayPrefs) change,
) async {
  final repository = ref.read(profileRepositoryProvider);
  try {
    final profile = await repository.get();
    await repository.save(profile.copyWith(display: change(profile.display)));
  } on Exception catch (e, s) {
    _log.warning('Cannot save the display settings', e, s);
  }
}

/// The "Reading" section: size, spacing, dimming, mode and palettes.
class ReadingSection extends ConsumerWidget {
  /// Creates the section for the current [display] preferences.
  const new({required this.display, super.key});

  /// Current display preferences.
  final DisplayPrefs display;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Reading', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(child: Text('Font size')),
            OutlinedButton(
              onPressed: display.fontSize <= DisplayPrefs.minFontSize
                  ? null
                  : () => unawaited(
                      _updateDisplay(
                        ref,
                        (d) => d.copyWith(fontSize: d.fontSize - 1),
                      ),
                    ),
              child: const Text('A−'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(display.fontSize.round().toString()),
            ),
            OutlinedButton(
              onPressed: display.fontSize >= DisplayPrefs.maxFontSize
                  ? null
                  : () => unawaited(
                      _updateDisplay(
                        ref,
                        (d) => d.copyWith(fontSize: d.fontSize + 1),
                      ),
                    ),
              child: const Text('A+'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Line spacing'),
        _PrefSlider(
          key: const Key('line-height'),
          min: DisplayPrefs.minLineHeight,
          max: DisplayPrefs.maxLineHeight,
          divisions: 15,
          value: display.lineHeight,
          onSave: (v) => unawaited(
            _updateDisplay(
              ref,
              (d) => d.copyWith(lineHeight: (v * 10).round() / 10),
            ),
          ),
        ),
        const Text('Dimming'),
        _PrefSlider(
          key: const Key('dim'),
          min: 0,
          max: DisplayPrefs.maxDim,
          divisions: 16,
          value: display.dim,
          onSave: (v) => unawaited(
            _updateDisplay(ref, (d) => d.copyWith(dim: (v * 20).round() / 20)),
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<DisplayMode>(
          segments: const [
            ButtonSegment(value: DisplayMode.day, label: Text('День')),
            ButtonSegment(value: DisplayMode.night, label: Text('Ночь')),
          ],
          selected: {display.mode},
          onSelectionChanged: (s) =>
              unawaited(_updateDisplay(ref, (d) => d.copyWith(mode: s.first))),
        ),
        const SizedBox(height: 16),
        _PaletteEditor(
          idPrefix: 'day',
          title: 'Day palette',
          palette: display.day,
          presets: dayPresets,
          fontSize: display.fontSize,
          lineHeight: display.lineHeight,
          onChanged: (p) =>
              unawaited(_updateDisplay(ref, (d) => d.copyWith(day: p))),
        ),
        const SizedBox(height: 16),
        _PaletteEditor(
          idPrefix: 'night',
          title: 'Night palette',
          palette: display.night,
          presets: nightPresets,
          fontSize: display.fontSize,
          lineHeight: display.lineHeight,
          onChanged: (p) =>
              unawaited(_updateDisplay(ref, (d) => d.copyWith(night: p))),
        ),
      ],
    );
  }
}

class _PaletteEditor extends StatelessWidget {
  const new({
    required this.idPrefix,
    required this.title,
    required this.palette,
    required this.presets,
    required this.fontSize,
    required this.lineHeight,
    required this.onChanged,
  });

  final String idPrefix;
  final String title;
  final Palette palette;
  final List<(int, int)> presets;
  final double fontSize;
  final double lineHeight;
  final ValueChanged<Palette> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = contrastRatio(palette.text, palette.background);
    final low = ratio < minContrast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < presets.length; i++)
              _Swatch(
                key: Key('$idPrefix-preset-$i'),
                palette: Palette(
                  text: presets[i].$1,
                  background: presets[i].$2,
                ),
                selected:
                    palette.text == presets[i].$1 &&
                    palette.background == presets[i].$2,
                onTap: () => onChanged(
                  Palette(text: presets[i].$1, background: presets[i].$2),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _HexField(
                key: Key('$idPrefix-background'),
                label: 'Background (HEX)',
                value: palette.background,
                onValid: (c) =>
                    onChanged(Palette(text: palette.text, background: c)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _HexField(
                key: Key('$idPrefix-text'),
                label: 'Text (HEX)',
                value: palette.text,
                onValid: (c) =>
                    onChanged(Palette(text: c, background: palette.background)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          key: Key('$idPrefix-sample'),
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: Color(palette.background),
          child: Text(
            'The quick brown fox jumps over the lazy dog. '
            'Reading in your own language of colours is easier on the eyes.',
            style: TextStyle(
              color: Color(palette.text),
              fontSize: fontSize,
              height: lineHeight,
            ),
          ),
        ),
        if (low)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              key: Key('$idPrefix-contrast-warning'),
              'Low contrast: ${ratio.toStringAsFixed(1)}:1, '
              'at least 4.5:1 is easier to read.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const new({
    required this.palette,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final Palette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      selected: selected,
      label:
          'Palette ${formatHexColor(palette.text)} on '
          '${formatHexColor(palette.background)}',
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color(palette.background),
            border: Border.all(
              color: selected ? outline : Colors.grey,
              width: selected ? 3 : 1,
            ),
          ),
          child: Text('Аа', style: TextStyle(color: Color(palette.text))),
        ),
      ),
    );
  }
}

class _HexField extends StatefulWidget {
  const new({
    required this.label,
    required this.value,
    required this.onValid,
    super.key,
  });

  final String label;
  final int value;
  final ValueChanged<int> onValid;

  @override
  State<_HexField> createState() => _HexFieldState();
}

class _HexFieldState extends State<_HexField> {
  late final TextEditingController _controller = TextEditingController(
    text: formatHexColor(widget.value),
  );
  String? _error;

  @override
  void didUpdateWidget(_HexField old) {
    super.didUpdateWidget(old);
    // A preset or another change replaced the colour: show it.
    if (old.value != widget.value &&
        parseHexColor(_controller.text) != widget.value) {
      _controller.text = formatHexColor(widget.value);
      _error = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _changed(String text) {
    final color = parseHexColor(text);
    if (color == null) {
      setState(() => _error = 'Six hex digits, for example F4ECD8');
      return;
    }
    setState(() => _error = null);
    if (color != widget.value) widget.onValid(color);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      autocorrect: false,
      maxLength: 7,
      textInputAction: TextInputAction.done,
      onChanged: _changed,
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: _error,
        counterText: '',
      ),
    );
  }
}

/// Slider that follows the finger and reports the value when released.
class _PrefSlider extends StatefulWidget {
  const new({
    required this.min,
    required this.max,
    required this.divisions,
    required this.value,
    required this.onSave,
    super.key,
  });

  final double min;
  final double max;
  final int divisions;
  final double value;
  final ValueChanged<double> onSave;

  @override
  State<_PrefSlider> createState() => _PrefSliderState();
}

class _PrefSliderState extends State<_PrefSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final value = (_dragging ?? widget.value).clamp(widget.min, widget.max);
    return Slider(
      min: widget.min,
      max: widget.max,
      divisions: widget.divisions,
      value: value,
      label: value.toStringAsFixed(2),
      onChanged: (v) => setState(() => _dragging = v),
      onChangeEnd: (v) {
        setState(() => _dragging = null);
        widget.onSave(v);
      },
    );
  }
}
