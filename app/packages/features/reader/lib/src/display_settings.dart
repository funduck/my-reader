import 'dart:io';

import 'package:core/domain_lookup.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_api/reader_api.dart';

final Logger _log = Logger('DisplaySettings');

/// Converts the profile's [DisplayPrefs] to the engine's [ReaderSettings].
///
/// `theme` follows `mode`; `text` and `background` come from the palette of
/// the active mode (the theme does not derive them). `fontFamily` is left to
/// the engine. A [FileTexture] whose file is gone gives no texture.
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
  FileTexture(:final path) => _fileTexture(path),
};

ImageProvider? _fileTexture(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    _log.warning('Background image is missing, drawing no texture: $path');
    return null;
  }
  return FileImage(file);
}
