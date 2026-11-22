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
  });

  /// Font family name, or `null` for the engine's default.
  final String? fontFamily;

  /// Font size in logical pixels; positive.
  final double fontSize;

  /// Colour theme.
  final ReaderTheme theme;

  /// Left and right padding of the text column in logical pixels;
  /// not negative.
  final double horizontalPadding;

  /// Returns a copy with the given fields replaced.
  ///
  /// [fontFamily] cannot be reset to `null` through this method; create a new
  /// [ReaderSettings] for that.
  ReaderSettings copyWith({
    String? fontFamily,
    double? fontSize,
    ReaderTheme? theme,
    double? horizontalPadding,
  }) => ReaderSettings(
    fontFamily: fontFamily ?? this.fontFamily,
    fontSize: fontSize ?? this.fontSize,
    theme: theme ?? this.theme,
    horizontalPadding: horizontalPadding ?? this.horizontalPadding,
  );

  @override
  bool operator ==(Object other) =>
      other is ReaderSettings &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.theme == theme &&
      other.horizontalPadding == horizontalPadding;

  @override
  int get hashCode =>
      Object.hash(fontFamily, fontSize, theme, horizontalPadding);

  @override
  String toString() =>
      'ReaderSettings($fontFamily, $fontSize, $theme, $horizontalPadding)';
}
