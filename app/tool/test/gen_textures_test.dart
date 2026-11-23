import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';

import '../gen_textures.dart';

List<List<int>> _pixels(List<int> png) {
  final image = img.decodePng(Uint8List.fromList(png))!;
  return [
    for (var y = 0; y < image.height; y++)
      [for (var x = 0; x < image.width; x++) image.getPixel(x, y).r.toInt()],
  ];
}

void main() {
  final first = generateTextures();

  test('three textures under 100 KB, 256x256 greyscale', () {
    expect(first.keys, ['paper', 'noise', 'linen']);
    for (final entry in first.entries) {
      expect(entry.value.length, lessThan(100 * 1024), reason: entry.key);
      final image = img.decodePng(entry.value)!;
      expect(image.width, 256);
      expect(image.height, 256);
      expect(image.numChannels, 1, reason: entry.key);
    }
  });

  test('two runs give byte-identical files', () {
    final second = generateTextures();
    for (final id in first.keys) {
      expect(second[id], first[id], reason: id);
    }
  });

  test('mean brightness is 0.5 +- 0.03 with a small spread', () {
    for (final entry in first.entries) {
      final all = _pixels(entry.value).expand((r) => r).toList();
      final mean = all.reduce((a, b) => a + b) / all.length;
      // Overlay leaves the page unchanged on average only for mean 0.5.
      expect(mean / 255, closeTo(0.5, 0.03), reason: entry.key);
      final range =
          all.reduce((a, b) => a > b ? a : b) -
          all.reduce((a, b) => a < b ? a : b);
      expect(range, lessThan(80), reason: entry.key);
    }
  });

  test('left edge continues into the right edge, top into bottom', () {
    const n = 256;
    for (final entry in first.entries) {
      final p = _pixels(entry.value);
      // Mean step between neighbours inside the tile, and across the seam.
      var inside = 0.0;
      var seamX = 0.0;
      var seamY = 0.0;
      for (var i = 0; i < n; i++) {
        for (var j = 0; j < n - 1; j++) {
          inside += (p[i][j + 1] - p[i][j]).abs();
          inside += (p[j + 1][i] - p[j][i]).abs();
        }
        seamX += (p[i][0] - p[i][n - 1]).abs();
        seamY += (p[0][i] - p[n - 1][i]).abs();
      }
      inside /= 2 * n * (n - 1);
      seamX /= n;
      seamY /= n;
      // A cropped (non-toroidal) texture jumps far more across the seam.
      expect(seamX, lessThanOrEqualTo(inside * 1.25 + 0.5), reason: entry.key);
      expect(seamY, lessThanOrEqualTo(inside * 1.25 + 0.5), reason: entry.key);
    }
  });
}
