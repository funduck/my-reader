import 'package:material_ui/material_ui.dart';
import 'package:reader_api/reader_api.dart';

/// Colours and text styles derived from [ReaderSettings].
@immutable
final class ReaderStyle {
  /// Derives the style from [settings].
  factory fromSettings(ReaderSettings settings) {
    final dark = settings.theme == ReaderTheme.dark;
    return ReaderStyle._(
      settings: settings,
      background: dark ? const Color(0xFF121212) : const Color(0xFFFFFBF5),
      text: dark ? const Color(0xFFE0E0E0) : const Color(0xFF212121),
      link: dark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0),
      muted: dark ? const Color(0xFF9E9E9E) : const Color(0xFF757575),
      highlight: dark ? const Color(0x66FFD54F) : const Color(0x80FFEB3B),
    );
  }

  const new _({
    required this.settings,
    required this.background,
    required this.text,
    required this.link,
    required this.muted,
    required this.highlight,
  });

  /// The settings this style was derived from.
  final ReaderSettings settings;

  /// Page background.
  final Color background;

  /// Body text colour.
  final Color text;

  /// Colour of link text.
  final Color link;

  /// Colour of secondary elements: quote bar, bullets, captions.
  final Color muted;

  /// Background of text marked by `highlight`.
  final Color highlight;

  /// Line height factor of body text.
  static const double lineHeight = 1.5;

  /// Vertical padding above and below each block.
  static const double blockPadding = 8;

  /// Style of body text.
  TextStyle get body => TextStyle(
    fontFamily: settings.fontFamily,
    fontSize: settings.fontSize,
    height: lineHeight,
    color: text,
  );

  /// Style of a heading of [level] (1..6): bold and larger than [body].
  TextStyle heading(int level) {
    const scale = [2.0, 1.6, 1.35, 1.2, 1.1, 1.0];
    return body.copyWith(
      fontSize: settings.fontSize * scale[(level - 1).clamp(0, 5)],
      fontWeight: FontWeight.bold,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderStyle && other.settings == settings;

  @override
  int get hashCode => settings.hashCode;
}
