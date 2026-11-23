import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_simple/reader_simple.dart';

void main() {
  test('every built-in texture has a PNG under 100 KB in assets', () {
    expect(builtInTextures, ['paper', 'noise', 'linen']);
    for (final id in builtInTextures) {
      final file = File('assets/textures/$id.png');
      expect(file.existsSync(), isTrue, reason: id);
      expect(file.lengthSync(), lessThan(100 * 1024), reason: id);
    }
  });
}
