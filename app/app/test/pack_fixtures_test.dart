import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/pack_fixtures.dart';

void main() {
  test('embedded packs equal service/fixtures/packs', () {
    final dir = Directory('../../service/fixtures/packs');
    for (final entry in packFixturesBase64.entries) {
      final files = dir.listSync().whereType<File>().where(
        (f) => RegExp('/${entry.key}-[^/]*\\.sqlite\$').hasMatch(f.path),
      );
      expect(files, hasLength(1), reason: 'one ${entry.key} fixture file');
      expect(
        base64Decode(entry.value),
        files.single.readAsBytesSync(),
        reason:
            'test/support/pack_fixtures.dart is stale: re-embed '
            '${files.single.path} as base64 (70-character lines) into '
            "packFixturesBase64['${entry.key}']",
      );
    }
  });
}
