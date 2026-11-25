import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'reading_section.dart' show formatHexColor, parseHexColor;

/// Hue and saturation at [position] on a wheel of [size], with the hue of
/// red on the right and growing clockwise; outside the rim the saturation is
/// clamped to 1.
({double hue, double saturation}) wheelHueSaturation(
  Offset position,
  Size size,
) {
  final radius = size.shortestSide / 2;
  final delta = position - size.center(Offset.zero);
  final hue = (math.atan2(delta.dy, delta.dx) * 180 / math.pi + 360) % 360;
  final saturation = radius == 0
      ? 0.0
      : (delta.distance / radius).clamp(0.0, 1.0);
  return (hue: hue, saturation: saturation);
}

/// Offset of [hue] and [saturation] on a wheel of [size], the inverse of
/// [wheelHueSaturation].
Offset wheelOffset(double hue, double saturation, Size size) {
  final radius = size.shortestSide / 2;
  final angle = hue * math.pi / 180;
  return size.center(Offset.zero) +
      Offset(math.cos(angle), math.sin(angle)) * radius * saturation;
}

/// Shows a dialog with a colour wheel, a brightness slider and a HEX field,
/// starting at [initial]; returns the chosen opaque ARGB colour, or `null`
/// when the dialog is cancelled.
Future<int?> showColorPicker(
  BuildContext context, {
  required String title,
  required int initial,
}) => showDialog<int>(
  context: context,
  builder: (_) => ColorPickerDialog(title: title, initial: initial),
);

/// Dialog of [showColorPicker].
class ColorPickerDialog extends StatefulWidget {
  /// Creates the dialog for the opaque ARGB [initial] colour.
  const new({required this.title, required this.initial, super.key});

  /// What is being picked, for example "Day background".
  final String title;

  /// Colour the dialog starts at, opaque ARGB.
  final int initial;

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  // Kept as HSV, not as the ARGB value: black and greys have no hue, and
  // the hue must survive dragging the brightness to zero and back.
  late HSVColor _hsv = HSVColor.fromColor(Color(widget.initial));
  late final TextEditingController _hex = TextEditingController(
    text: formatHexColor(widget.initial),
  );
  String? _hexError;

  int get _argb => _hsv.toColor().toARGB32() | 0xFF000000;

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _setHsv(HSVColor hsv) {
    setState(() {
      _hsv = hsv;
      _hex.text = formatHexColor(_argb);
      _hexError = null;
    });
  }

  void _hexChanged(String text) {
    final color = parseHexColor(text);
    setState(() {
      if (color == null) {
        _hexError = 'Six hex digits';
        return;
      }
      _hexError = null;
      if (color != _argb) _hsv = HSVColor.fromColor(Color(color));
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ColorWheel(
                key: const Key('color-wheel'),
                hsv: _hsv,
                onChanged: (hue, saturation) =>
                    _setHsv(_hsv.withHue(hue).withSaturation(saturation)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.brightness_6_outlined),
                  Expanded(
                    child: Slider(
                      key: const Key('color-brightness'),
                      value: _hsv.value,
                      label: '${(_hsv.value * 100).round()}%',
                      semanticFormatterCallback: (v) =>
                          'Brightness ${(v * 100).round()}%',
                      onChanged: (v) => _setHsv(_hsv.withValue(v)),
                    ),
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Preview(before: widget.initial, after: _argb),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const Key('color-hex'),
                      controller: _hex,
                      autocorrect: false,
                      maxLength: 7,
                      textInputAction: TextInputAction.done,
                      onChanged: _hexChanged,
                      decoration: InputDecoration(
                        labelText: 'HEX',
                        prefixText: '#',
                        errorText: _hexError,
                        counterText: '',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('color-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('color-select'),
          onPressed: _hexError == null
              ? () => Navigator.of(context).pop(_argb)
              : null,
          child: const Text('Select'),
        ),
      ],
    );
  }
}

/// The old colour over the new one, so the change reads at a glance.
class _Preview extends StatelessWidget {
  const new({required this.before, required this.after});

  final int before;
  final int after;

  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).colorScheme.outline;
    return Semantics(
      label: 'Was ${formatHexColor(before)}, now ${formatHexColor(after)}',
      child: ExcludeSemantics(
        child: Container(
          width: 48,
          height: 48,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: ColoredBox(color: Color(before))),
              Expanded(child: ColoredBox(color: Color(after))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hue around, saturation from the centre out; the brightness of [hsv]
/// darkens the whole wheel.
class _ColorWheel extends StatelessWidget {
  const new({required this.hsv, required this.onChanged, super.key});

  final HSVColor hsv;
  final void Function(double hue, double saturation) onChanged;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          void report(Offset position) {
            final hs = wheelHueSaturation(position, size);
            onChanged(hs.hue, hs.saturation);
          }

          return Semantics(
            label:
                'Colour wheel, hue ${hsv.hue.round()} degrees, '
                'saturation ${(hsv.saturation * 100).round()}%. '
                'Type the colour in the HEX field instead.',
            child: GestureDetector(
              onTapDown: (d) => report(d.localPosition),
              onPanStart: (d) => report(d.localPosition),
              onPanUpdate: (d) => report(d.localPosition),
              child: CustomPaint(
                size: size,
                painter: _WheelPainter(
                  hue: hsv.hue,
                  saturation: hsv.saturation,
                  value: hsv.value,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  new({required this.hue, required this.saturation, required this.value});

  final double hue;
  final double saturation;
  final double value;

  static const List<Color> _hues = [
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas
      ..drawCircle(
        center,
        radius,
        Paint()..shader = const SweepGradient(colors: _hues).createShader(rect),
      )
      ..drawCircle(
        center,
        radius,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          ).createShader(rect),
      )
      ..drawCircle(
        center,
        radius,
        Paint()..color = Color.fromRGBO(0, 0, 0, 1 - value),
      );

    final thumb = wheelOffset(hue, saturation, size);
    final fill = HSVColor.fromAHSV(1, hue, saturation, value).toColor();
    canvas
      ..drawCircle(thumb, 11, Paint()..color = fill)
      ..drawCircle(
        thumb,
        11,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFFFFFFFF),
      )
      ..drawCircle(
        thumb,
        12.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x99000000),
      );
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.hue != hue || old.saturation != saturation || old.value != value;
}
