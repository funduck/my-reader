import 'dart:io';

import 'package:core/domain_lookup.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_api/reader_api.dart';

/// Converts the profile's [DisplayPrefs] to the engine's [ReaderSettings].
///
/// `theme` follows `mode`; `text` and `background` come from the palette of
/// the active mode (the theme does not derive them). `fontFamily` is left to
/// the engine.
ReaderSettings readerSettingsFrom(DisplayPrefs prefs) {
  final palette = prefs.palette;
  return ReaderSettings(
    fontSize: prefs.fontSize,
    lineHeight: prefs.lineHeight,
    theme: prefs.mode == DisplayMode.night
        ? ReaderTheme.dark
        : ReaderTheme.light,
    text: Color(palette.text),
    background: Color(palette.background),
    texture: _texture(prefs.texture),
    textureOpacity: prefs.textureOpacity,
    dim: prefs.dim,
    edgeTaps: prefs.edgeTaps,
  );
}

ImageProvider? _texture(BackgroundTexture texture) => switch (texture) {
  NoTexture() => null,
  BuiltInTexture(:final id) => AssetImage(
    'packages/reader_simple/assets/textures/$id.png',
  ),
  FileTexture(:final path) => FileImage(File(path)),
};
