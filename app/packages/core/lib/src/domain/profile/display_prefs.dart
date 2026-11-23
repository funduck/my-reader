import 'package:meta/meta.dart';

/// Day or night colours of the reading surface.
enum DisplayMode {
  /// The day palette.
  day,

  /// The night palette.
  night;

  /// Reads a mode; anything unknown gives [day].
  static DisplayMode fromJson(Object? json) => json == 'night' ? night : day;

  /// JSON form: the enum name.
  String toJson() => name;
}

/// Text and background colours, ARGB `int`s (the core has no Flutter).
@immutable
final class Palette {
  /// Creates a palette.
  const new({required this.text, required this.background});

  /// Reads a palette; missing or invalid colours take those of [fallback].
  factory fromJson(Object? json, Palette fallback) {
    if (json is! Map<String, Object?>) return fallback;
    final text = json['text'];
    final background = json['background'];
    return Palette(
      text: text is int ? text & 0xFFFFFFFF : fallback.text,
      background: background is int
          ? background & 0xFFFFFFFF
          : fallback.background,
    );
  }

  /// Text colour, `0xAARRGGBB`.
  final int text;

  /// Background colour, `0xAARRGGBB`.
  final int background;

  /// JSON form.
  Map<String, Object?> toJson() => {'text': text, 'background': background};

  @override
  bool operator ==(Object other) =>
      other is Palette && other.text == text && other.background == background;

  @override
  int get hashCode => Object.hash(text, background);
}

/// Texture drawn over the background colour.
@immutable
sealed class BackgroundTexture {
  /// Base constructor.
  const new();

  /// Reads a texture; missing or malformed values give [NoTexture].
  factory fromJson(Object? json) {
    if (json is! Map<String, Object?>) return const NoTexture();
    switch (json['type']) {
      case 'builtIn':
        final id = json['id'];
        return id is String && id.isNotEmpty
            ? BuiltInTexture(id)
            : const NoTexture();
      case 'file':
        final path = json['path'];
        return path is String && path.isNotEmpty
            ? FileTexture(path)
            : const NoTexture();
      default:
        return const NoTexture();
    }
  }

  /// JSON form: `{type: none}`, `{type: builtIn, id}` or `{type: file, path}`.
  Map<String, Object?> toJson();
}

/// No texture: the plain background colour.
@immutable
final class NoTexture extends BackgroundTexture {
  /// Creates the value.
  const new();

  @override
  Map<String, Object?> toJson() => {'type': 'none'};

  @override
  bool operator ==(Object other) => other is NoTexture;

  @override
  int get hashCode => (NoTexture).hashCode;
}

/// A texture shipped with the app, by [id].
@immutable
final class BuiltInTexture extends BackgroundTexture {
  /// Creates a texture with [id].
  const new(this.id);

  /// Identifier of the bundled texture.
  final String id;

  @override
  Map<String, Object?> toJson() => {'type': 'builtIn', 'id': id};

  @override
  bool operator ==(Object other) => other is BuiltInTexture && other.id == id;

  @override
  int get hashCode => Object.hash(BuiltInTexture, id);
}

/// A texture from a file the user picked.
@immutable
final class FileTexture extends BackgroundTexture {
  /// Creates a texture from [path].
  const new(this.path);

  /// Absolute path of the image file.
  final String path;

  @override
  Map<String, Object?> toJson() => {'type': 'file', 'path': path};

  @override
  bool operator ==(Object other) => other is FileTexture && other.path == path;

  @override
  int get hashCode => Object.hash(FileTexture, path);
}

/// A font the user picked: the copy kept by the app and its family name.
@immutable
final class FontChoice {
  /// Creates a choice of the font file at [path] registered as [family].
  const new({required this.path, required this.family});

  /// Reads a choice; a missing or malformed value gives `null` (the system
  /// font).
  static FontChoice? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final path = json['path'];
    final family = json['family'];
    if (path is! String || path.isEmpty) return null;
    if (family is! String || family.isEmpty) return null;
    return FontChoice(path: path, family: family);
  }

  /// Absolute path of the copy in the application support directory.
  final String path;

  /// Family name the font is registered under; also shown in the list.
  final String family;

  /// JSON form: `{path, family}`.
  Map<String, Object?> toJson() => {'path': path, 'family': family};

  @override
  bool operator ==(Object other) =>
      other is FontChoice && other.path == path && other.family == family;

  @override
  int get hashCode => Object.hash(FontChoice, path, family);
}

/// How the reader looks: size, spacing, colours, texture, dimming, paging.
///
/// Numbers outside their range are clamped by the constructor and
/// [DisplayPrefs.fromJson]. The texture and dimming are shared by both modes.
@immutable
final class DisplayPrefs {
  /// Creates preferences; every field has a default, numbers are clamped.
  const new({
    double fontSize = 18,
    double lineHeight = 1.5,
    this.mode = DisplayMode.day,
    this.day = defaultDay,
    this.night = defaultNight,
    this.texture = const NoTexture(),
    double textureOpacity = 0.5,
    double dim = 0,
    this.edgeTaps = true,
    this.translateOnSelect = false,
    this.font,
    this.fontFolder,
  }) : fontSize = fontSize < minFontSize
           ? minFontSize
           : (fontSize > maxFontSize ? maxFontSize : fontSize),
       lineHeight = lineHeight < minLineHeight
           ? minLineHeight
           : (lineHeight > maxLineHeight ? maxLineHeight : lineHeight),
       textureOpacity = textureOpacity < 0
           ? 0
           : (textureOpacity > 1 ? 1 : textureOpacity),
       dim = dim < 0 ? 0 : (dim > maxDim ? maxDim : dim);

  /// Reads preferences; missing or invalid fields take defaults.
  factory fromJson(Object? json) {
    if (json is! Map<String, Object?>) return const DisplayPrefs();
    double number(String key, double fallback) {
      final v = json[key];
      return v is num && v.isFinite ? v.toDouble() : fallback;
    }

    final edgeTaps = json['edgeTaps'];
    return DisplayPrefs(
      fontSize: number('fontSize', 18),
      lineHeight: number('lineHeight', 1.5),
      mode: DisplayMode.fromJson(json['mode']),
      day: Palette.fromJson(json['day'], defaultDay),
      night: Palette.fromJson(json['night'], defaultNight),
      texture: BackgroundTexture.fromJson(json['texture']),
      textureOpacity: number('textureOpacity', 0.5),
      dim: number('dim', 0),
      edgeTaps: edgeTaps is! bool || edgeTaps,
      translateOnSelect: json['translateOnSelect'] == true,
      font: FontChoice.fromJson(json['font']),
      fontFolder: switch (json['fontFolder']) {
        final String folder when folder.isNotEmpty => folder,
        _ => null,
      },
    );
  }

  /// Smallest font size.
  static const double minFontSize = 12;

  /// Largest font size.
  static const double maxFontSize = 40;

  /// Smallest line height factor.
  static const double minLineHeight = 1;

  /// Largest line height factor.
  static const double maxLineHeight = 2.5;

  /// Largest dimming share.
  static const double maxDim = 0.8;

  /// Default day palette.
  static const Palette defaultDay = Palette(
    text: 0xFF212121,
    background: 0xFFFFFBF5,
  );

  /// Default night palette.
  static const Palette defaultNight = Palette(
    text: 0xFFE0E0E0,
    background: 0xFF121212,
  );

  /// Font size in logical pixels, 12..40.
  final double fontSize;

  /// Line height factor, 1.0..2.5.
  final double lineHeight;

  /// Which palette is active.
  final DisplayMode mode;

  /// Day palette.
  final Palette day;

  /// Night palette.
  final Palette night;

  /// Texture over the background, shared by both modes.
  final BackgroundTexture texture;

  /// Opacity of the texture, 0..1.
  final double textureOpacity;

  /// Share of dimming over the page, 0..0.8.
  final double dim;

  /// Whether a tap on the screen edge turns the page.
  final bool edgeTaps;

  /// Whether a finished selection opens the translation at once.
  ///
  /// Off by default; an old profile without the field reads as `false`.
  final bool translateOnSelect;

  /// The chosen font, or `null` for the system font.
  final FontChoice? font;

  /// The last folder fonts were looked for in, or `null`.
  final String? fontFolder;

  /// The palette of the active [mode].
  Palette get palette => mode == DisplayMode.day ? day : night;

  /// Copy with some fields replaced.
  ///
  /// [font] and [fontFolder] take a function so that `() => null` clears them.
  DisplayPrefs copyWith({
    double? fontSize,
    double? lineHeight,
    DisplayMode? mode,
    Palette? day,
    Palette? night,
    BackgroundTexture? texture,
    double? textureOpacity,
    double? dim,
    bool? edgeTaps,
    bool? translateOnSelect,
    FontChoice? Function()? font,
    String? Function()? fontFolder,
  }) => DisplayPrefs(
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    mode: mode ?? this.mode,
    day: day ?? this.day,
    night: night ?? this.night,
    texture: texture ?? this.texture,
    textureOpacity: textureOpacity ?? this.textureOpacity,
    dim: dim ?? this.dim,
    edgeTaps: edgeTaps ?? this.edgeTaps,
    translateOnSelect: translateOnSelect ?? this.translateOnSelect,
    font: font == null ? this.font : font(),
    fontFolder: fontFolder == null ? this.fontFolder : fontFolder(),
  );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'mode': mode.toJson(),
    'day': day.toJson(),
    'night': night.toJson(),
    'texture': texture.toJson(),
    'textureOpacity': textureOpacity,
    'dim': dim,
    'edgeTaps': edgeTaps,
    'translateOnSelect': translateOnSelect,
    'font': font?.toJson(),
    'fontFolder': fontFolder,
  };

  @override
  bool operator ==(Object other) =>
      other is DisplayPrefs &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight &&
      other.mode == mode &&
      other.day == day &&
      other.night == night &&
      other.texture == texture &&
      other.textureOpacity == textureOpacity &&
      other.dim == dim &&
      other.edgeTaps == edgeTaps &&
      other.translateOnSelect == translateOnSelect &&
      other.font == font &&
      other.fontFolder == fontFolder;

  @override
  int get hashCode => Object.hash(
    fontSize,
    lineHeight,
    mode,
    day,
    night,
    texture,
    textureOpacity,
    dim,
    edgeTaps,
    translateOnSelect,
    font,
    fontFolder,
  );
}
