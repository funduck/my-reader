import 'dart:io';
import 'dart:typed_data';

import 'package:core/domain_lookup.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_test/flutter_test.dart';

import 'font_fixture.dart';

void main() {
  group('parseFontName', () {
    test('reads family and style from nameID 1/2', () async {
      final name = await parseFontName(
        buildTestFont([(3, 1, 'Lora'), (3, 2, 'Italic')]),
      );
      expect(name?.family, 'Lora');
      expect(name?.style, 'Italic');
      expect(name?.display, 'Lora Italic');
    });

    test('prefers nameID 16/17 over 1/2', () async {
      final name = await parseFontName(
        buildTestFont([
          (3, 1, 'Lora Medium'),
          (3, 2, 'Regular'),
          (3, 16, 'Lora'),
          (3, 17, 'Medium'),
        ]),
      );
      expect(name?.family, 'Lora');
      expect(name?.style, 'Medium');
    });

    test('reads Macintosh Latin-1 records and OpenType files', () async {
      final name = await parseFontName(
        buildTestFont([(1, 1, 'Café'), (1, 2, 'Bold')], version: 0x4F54544F),
      );
      expect(name?.display, 'Café Bold');
    });

    test('a missing style gives only the family', () async {
      final name = await parseFontName(buildTestFont([(3, 1, 'Solo')]));
      expect(name?.display, 'Solo');
    });

    test('broken data gives null', () async {
      expect(await parseFontName(Uint8List(0)), isNull);
      expect(await parseFontName(Uint8List.fromList([1, 2, 3])), isNull);
      expect(await parseFontName(Uint8List(200)), isNull);
      final good = buildTestFont([(3, 1, 'Lora')]);
      expect(
        await parseFontName(Uint8List.sublistView(good, 0, good.length - 4)),
        isNull,
      );
      // A collection header is not a single font.
      final collection = Uint8List.fromList(good)..[0] = 0x74; // 't'
      expect(await parseFontName(collection), isNull);
      expect(await parseFontName(buildTestFont([(3, 4, 'Full')])), isNull);
    });
  });

  group('readFontNameFromFile', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('font_name'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('reads a file; a missing or broken one gives null', () async {
      final good = File('${dir.path}/a.ttf')
        ..writeAsBytesSync(buildTestFont([(3, 1, 'Lora'), (3, 2, 'Regular')]));
      final bad = File('${dir.path}/b.ttf')..writeAsStringSync('not a font');
      expect((await readFontNameFromFile(good.path))?.display, 'Lora Regular');
      expect(await readFontNameFromFile(bad.path), isNull);
      expect(await readFontNameFromFile('${dir.path}/none.ttf'), isNull);
    });
  });

  test('loadUserFont reports a missing file without throwing', () async {
    final ok = await loadUserFont(
      const FontChoice(path: '/no/such/font.ttf', family: 'Gone'),
    );
    expect(ok, isFalse);
  });
}
