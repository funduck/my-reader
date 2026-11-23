import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// Colour theme of the reading surface.
enum ReaderTheme {
  /// Dark text on a light background.
  light,

  /// Light text on a dark background.
  dark,
}

/// Display settings of the reader (R-3).
///
/// The engine applies them without reloading the book and keeps the current
/// position.
@immutable
final class ReaderSettings {
  /// Creates settings; defaults give a readable light layout.
  const new({
    this.fontFamily,
    this.fontSize = 18,
    this.theme = ReaderTheme.light,
    this.horizontalPadding = 16,
    this.lineHeight = 1.5,
    this.text = const Color(0xFF212121),
    this.background = const Color(0xFFFFFBF5),
    this.texture,
    this.textureOpacity = 0.5,
    this.dim = 0,
    this.edgeTaps = true,
    this.translateOnSelect = false,
  });

  /// Font family name, or `null` for the engine's default.
  final String? fontFamily;

  /// Font size in logical pixels; positive.
  final double fontSize;

  /// Colour theme; derived colours (link, highlight) depend on it, while
  /// [text] and [background] are taken from the fields below.
  final ReaderTheme theme;

  /// Left and right padding of the text column in logical pixels;
  /// not negative.
  final double horizontalPadding;

  /// Line height factor of body text; positive.
  final double lineHeight;

  /// Body text colour.
  final Color text;

  /// Page background colour.
  final Color background;

  /// Tiled image over the background, or `null` for none.
  final ImageProvider? texture;

  /// Opacity of [texture], 0..1.
  final double textureOpacity;

  /// Share of black laid over the page, 0..1.
  final double dim;

  /// Whether a tap on the screen edge turns the page.
  final bool edgeTaps;

  /// Whether a ready selection is sent at once as `TextSelected` (`true`), or
  /// the engine first shows a toolbar with "Translate" and "Copy" (`false`).
  final bool translateOnSelect;

  /// Returns a copy with the given fields replaced.
  ///
  /// [fontFamily] cannot be reset to `null` through this method; create a new
  /// [ReaderSettings] for that. [texture] takes a function so that
  /// `() => null` clears it.
  ReaderSettings copyWith({
    String? fontFamily,
    double? fontSize,
    ReaderTheme? theme,
    double? horizontalPadding,
    double? lineHeight,
    Color? text,
    Color? background,
    ImageProvider? Function()? texture,
    double? textureOpacity,
    double? dim,
    bool? edgeTaps,
    bool? translateOnSelect,
  }) => ReaderSettings(
    fontFamily: fontFamily ?? this.fontFamily,
    fontSize: fontSize ?? this.fontSize,
    theme: theme ?? this.theme,
    horizontalPadding: horizontalPadding ?? this.horizontalPadding,
    lineHeight: lineHeight ?? this.lineHeight,
    text: text ?? this.text,
    background: background ?? this.background,
    texture: texture != null ? texture() : this.texture,
    textureOpacity: textureOpacity ?? this.textureOpacity,
    dim: dim ?? this.dim,
    edgeTaps: edgeTaps ?? this.edgeTaps,
    translateOnSelect: translateOnSelect ?? this.translateOnSelect,
  );

  @override
  bool operator ==(Object other) =>
      other is ReaderSettings &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.theme == theme &&
      other.horizontalPadding == horizontalPadding &&
      other.lineHeight == lineHeight &&
      other.text == text &&
      other.background == background &&
      other.texture == texture &&
      other.textureOpacity == textureOpacity &&
      other.dim == dim &&
      other.edgeTaps == edgeTaps &&
      other.translateOnSelect == translateOnSelect;

  @override
  int get hashCode => Object.hash(
    fontFamily,
    fontSize,
    theme,
    horizontalPadding,
    lineHeight,
    text,
    background,
    texture,
    textureOpacity,
    dim,
    edgeTaps,
    translateOnSelect,
  );

  @override
  String toString() =>
      'ReaderSettings($fontFamily, $fontSize, $theme, $horizontalPadding, '
      '$lineHeight, $text, $background, $texture, $textureOpacity, $dim, '
      '$edgeTaps, $translateOnSelect)';
}
