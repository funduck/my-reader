/// Generates the built-in reader background textures (T-082).
///
///     dart run tool/gen_textures.dart [output-dir]
///
/// Writes `paper.png`, `noise.png` and `linen.png` (256x256, greyscale) to
/// `packages/reader_simple/assets/textures/` by default. Output is fully
/// deterministic: fixed seed, an own integer hash instead of `dart:math`
/// `Random`, nothing is read from the network. All noise is built on a torus
/// (the lattice wraps), so each texture tiles without a visible seam.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Side of every texture in pixels.
const int textureSize = 256;

const int _seed = 0x5EED082;

/// Ids of the generated textures, in the order of `builtInTextures`.
const List<String> textureIds = ['paper', 'noise', 'linen'];

/// Renders every built-in texture as PNG bytes, keyed by id.
Map<String, Uint8List> generateTextures() => {
  for (final id in textureIds) id: _encode(_render(id)),
};

Uint8List _encode(List<double> pixels) {
  final image = img.Image(
    width: textureSize,
    height: textureSize,
    numChannels: 1,
  );
  for (var y = 0; y < textureSize; y++) {
    for (var x = 0; x < textureSize; x++) {
      final v = (pixels[y * textureSize + x] * 255).round().clamp(0, 255);
      image.setPixelR(x, y, v);
    }
  }
  return img.encodePng(image, level: 9);
}

List<double> _render(String id) => switch (id) {
  'paper' => _paper(),
  'noise' => _noise(),
  'linen' => _linen(),
  _ => throw ArgumentError.value(id, 'id'),
};

/// 32-bit integer hash of three values; stable on every platform.
int _hash(int a, int b, int c) {
  var h = (a * 0x27D4EB2D) ^ (b * 0x165667B1) ^ (c * 0x9E3779B1) ^ _seed;
  h &= 0xFFFFFFFF;
  h = ((h ^ (h >> 15)) * 0x2C1B3C6D) & 0xFFFFFFFF;
  h = ((h ^ (h >> 12)) * 0x297A2D39) & 0xFFFFFFFF;
  return (h ^ (h >> 15)) & 0xFFFFFFFF;
}

/// Hash as a number in [-1, 1].
double _unit(int a, int b, int c) => _hash(a, b, c) / 0x7FFFFFFF - 1;

double _smooth(double t) => t * t * (3 - 2 * t);

/// Value noise on a torus with [cx] x [cy] lattice cells; the lattice wraps,
/// so the result is periodic with the texture size. Range [-1, 1].
double _tileNoise(double u, double v, int cx, int cy, int salt) {
  final x = u * cx;
  final y = v * cy;
  final x0 = x.floor();
  final y0 = y.floor();
  final fx = _smooth(x - x0);
  final fy = _smooth(y - y0);
  double corner(int dx, int dy) => _unit((x0 + dx) % cx, (y0 + dy) % cy, salt);
  final top = corner(0, 0) + (corner(1, 0) - corner(0, 0)) * fx;
  final bottom = corner(0, 1) + (corner(1, 1) - corner(0, 1)) * fx;
  return top + (bottom - top) * fy;
}

List<double> _field(double Function(double u, double v, int x, int y) f) {
  final out = List<double>.filled(textureSize * textureSize, 0);
  for (var y = 0; y < textureSize; y++) {
    for (var x = 0; x < textureSize; x++) {
      out[y * textureSize + x] = f(x / textureSize, y / textureSize, x, y);
    }
  }
  return out;
}

/// Rescales [pixels] to mean 0.5 and standard deviation [sigma] (0..1), so
/// the texture is clearly visible; the visibility is set by the slider, not
/// by the picture. An affine map keeps the torus seamless.
List<double> _normalize(List<double> pixels, double sigma) {
  final n = pixels.length;
  final mean = pixels.reduce((a, b) => a + b) / n;
  var sum = 0.0;
  for (final p in pixels) {
    sum += (p - mean) * (p - mean);
  }
  final k = sigma / math.sqrt(sum / n);
  return [for (final p in pixels) (0.5 + (p - mean) * k).clamp(0.0, 1.0)];
}

/// Soft noise with long fibres: coarse blobs plus stretched strands.
List<double> _paper() => _normalize(
  _field((u, v, x, y) {
    final blobs =
        0.6 * _tileNoise(u, v, 4, 4, 1) + 0.4 * _tileNoise(u, v, 8, 8, 2);
    final fibres =
        0.5 * _tileNoise(u, v, 48, 3, 3) + 0.5 * _tileNoise(u, v, 3, 48, 4);
    final grain = _unit(x, y, 5);
    return 0.5 * blobs + 0.8 * fibres + 0.25 * grain;
  }),
  0.14,
);

/// Fine noise, a little smoothed by a tiny lattice.
List<double> _noise() => _normalize(
  _field((u, v, x, y) {
    final fine = 0.5 * (_unit(x, y, 6) + _unit(x, y, 10));
    final soft = _tileNoise(u, v, 128, 128, 7);
    return fine + 0.5 * soft;
  }),
  0.15,
);

/// Plain weave: 4 px cells in a chessboard, warp threads run over the weft in
/// one half of the cells and under it in the other; each thread is a rounded
/// ridge, so the picture reads as woven cloth, not as a grid of dots.
List<double> _linen() => _normalize(
  _field((u, v, x, y) {
    final cellX = x ~/ 4;
    final cellY = y ~/ 4;
    final ridgeX = math.sin(math.pi * ((x % 4) + 0.5) / 4);
    final ridgeY = math.sin(math.pi * ((y % 4) + 0.5) / 4);
    final warpOver = (cellX + cellY).isEven;
    final weave = warpOver ? ridgeX : ridgeY;
    final slub = _tileNoise(u, v, 32, 32, 8);
    return weave + 0.35 * slub + 0.15 * _unit(x, y, 9);
  }),
  0.15,
);

void main(List<String> args) {
  final dir = Directory(
    args.isNotEmpty ? args.first : 'packages/reader_simple/assets/textures',
  )..createSync(recursive: true);
  generateTextures().forEach((id, bytes) {
    File('${dir.path}/$id.png').writeAsBytesSync(bytes);
    stdout.writeln('$id.png: ${bytes.length} bytes');
  });
}
