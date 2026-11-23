import 'dart:io';

import 'package:core/domain_lookup.dart';
import 'package:features_reader/features_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('a FileTexture with a missing file gives no texture', () {
    final dir = Directory.systemTemp.createTempSync('display_settings_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final prefs = const DisplayPrefs().copyWith(
      texture: FileTexture('${dir.path}/gone.png'),
    );
    expect(readerSettingsFrom(prefs).texture, isNull);
  });

  test('a FileTexture with an existing file gives a FileImage', () {
    final dir = Directory.systemTemp.createTempSync('display_settings_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/own.png')..writeAsBytesSync([1, 2, 3]);
    final prefs = const DisplayPrefs().copyWith(
      texture: FileTexture(file.path),
    );
    expect(readerSettingsFrom(prefs).texture, isA<FileImage>());
  });

  test('a built-in texture is an asset of reader_simple', () {
    final prefs = const DisplayPrefs().copyWith(
      texture: const BuiltInTexture('paper'),
    );
    final image = readerSettingsFrom(prefs).texture! as AssetImage;
    expect(image.assetName, 'packages/reader_simple/assets/textures/paper.png');
  });

  test('fontFamily comes from the font; without a font it is null', () {
    final dir = Directory.systemTemp.createTempSync('display_settings_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/f.ttf')..writeAsBytesSync([1, 2, 3]);
    final prefs = const DisplayPrefs().copyWith(
      font: () => FontChoice(path: file.path, family: 'Lora Regular'),
    );
    expect(readerSettingsFrom(prefs).fontFamily, 'Lora Regular');
    expect(readerSettingsFrom(const DisplayPrefs()).fontFamily, isNull);
  });

  test('a font whose file is gone gives null', () {
    final dir = Directory.systemTemp.createTempSync('display_settings_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final prefs = const DisplayPrefs().copyWith(
      font: () => FontChoice(path: '${dir.path}/gone.ttf', family: 'Gone'),
    );
    expect(readerSettingsFrom(prefs).fontFamily, isNull);
  });
}
