import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_simple/reader_simple.dart';

/// Greyscale values (0..1) of the PNG pixels, decoded by the engine.
Future<List<double>> _pixels(String id) async {
  final codec = await ui.instantiateImageCodec(
    File('assets/textures/$id.png').readAsBytesSync(),
  );
  final image = (await codec.getNextFrame()).image;
  final data = (await image.toByteData())!;
  return [
    for (var i = 0; i < data.lengthInBytes; i += 4) data.getUint8(i) / 255,
  ];
}

/// `overlay` of the background channel [s] and the texture pixel [d] (0..1),
/// then mixed in with [a], the texture opacity.
double _overlay(double s, double d, double a) {
  final o = d <= 0.5 ? 2 * s * d : 1 - 2 * (1 - s) * (1 - d);
  return s + a * (o - s);
}

/// Brightness (0..1) of the background [rgb] under the texture pixel [d].
double _blendedLuma(int rgb, double d, double a) {
  final r = _overlay(((rgb >> 16) & 0xFF) / 255, d, a);
  final g = _overlay(((rgb >> 8) & 0xFF) / 255, d, a);
  final b = _overlay((rgb & 0xFF) / 255, d, a);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

void main() {
  test('every built-in texture has a PNG under 100 KB in assets', () {
    expect(builtInTextures, ['paper', 'noise', 'linen']);
    for (final id in builtInTextures) {
      final file = File('assets/textures/$id.png');
      expect(file.existsSync(), isTrue, reason: id);
      expect(file.lengthSync(), lessThan(100 * 1024), reason: id);
    }
  });

  for (final background in [0x2B2419, 0xFFFBF5]) {
    for (final id in builtInTextures) {
      testWidgets(
        'texture $id at opacity 0.5 changes #${background.toRadixString(16)} '
        'by at least 4 % of brightness',
        (tester) async {
          final pixels = (await tester.runAsync(() => _pixels(id)))!;
          var lightest = 0.0;
          var darkest = 1.0;
          for (final d in pixels) {
            final y = _blendedLuma(background, d, 0.5);
            if (y > lightest) lightest = y;
            if (y < darkest) darkest = y;
          }
          expect(lightest - darkest, greaterThanOrEqualTo(0.04), reason: id);
        },
      );
    }
  }
}
