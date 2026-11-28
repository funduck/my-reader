import 'package:material_ui/material_ui.dart';
import 'package:reader_api/reader_api.dart';

/// How text of one [HighlightKind] is drawn: a background plate, an underline
/// or both; a `null` colour draws nothing of that sort.
///
/// The background is a rounded plate painted behind the text (T-123,
/// `highlight_plates.dart`); the underline is a text decoration.
@immutable
final class HighlightStyle {
  /// Creates a style; a style with neither colour draws nothing.
  const new({this.background, this.underline});

  /// Colour of the plate behind the text.
  final Color? background;

  /// Colour of a line under the text.
  final Color? underline;

  /// The text style that draws this highlight in the text itself: the
  /// underline only. The background is not a text style: a `backgroundColor`
  /// is a square box tight to the letters.
  TextStyle get textStyle => TextStyle(
    decoration: underline == null ? null : TextDecoration.underline,
    decorationColor: underline,
  );

  @override
  bool operator ==(Object other) =>
      other is HighlightStyle &&
      other.background == background &&
      other.underline == underline;

  @override
  int get hashCode => Object.hash(background, underline);
}

/// Colours and text styles derived from [ReaderSettings].
@immutable
final class ReaderStyle {
  /// Derives the style from [settings].
  factory fromSettings(ReaderSettings settings) {
    final dark = settings.theme == ReaderTheme.dark;
    return ReaderStyle._(
      settings: settings,
      background: settings.background,
      text: settings.text,
      link: dark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0),
      muted: Color.lerp(settings.text, settings.background, 0.45)!,
      highlights: dark ? _darkHighlights : _lightHighlights,
    );
  }

  const new _({
    required this.settings,
    required this.background,
    required this.text,
    required this.link,
    required this.muted,
    required this.highlights,
  });

  // Colours of the kinds, accepted in the demo (T-113): `focus` is the former
  // single highlight, the other kinds are fills of different hues. The user
  // will be able to change them with B-020.
  static const Map<HighlightKind, HighlightStyle> _lightHighlights = {
    HighlightKind.focus: HighlightStyle(background: Color(0x80FFEB3B)),
    HighlightKind.recent: HighlightStyle(background: Color(0x6666BB6A)),
    HighlightKind.lookedUp: HighlightStyle(background: Color(0x5542A5F5)),
    HighlightKind.cheatSheet: HighlightStyle(background: Color(0x55AB47BC)),
    HighlightKind.difficult: HighlightStyle(background: Color(0x55FF7043)),
  };

  static const Map<HighlightKind, HighlightStyle> _darkHighlights = {
    HighlightKind.focus: HighlightStyle(background: Color(0x66FFD54F)),
    HighlightKind.recent: HighlightStyle(background: Color(0x6681C784)),
    HighlightKind.lookedUp: HighlightStyle(background: Color(0x6664B5F6)),
    HighlightKind.cheatSheet: HighlightStyle(background: Color(0x66CE93D8)),
    HighlightKind.difficult: HighlightStyle(background: Color(0x66FF8A65)),
  };

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

  /// How each [HighlightKind] is drawn; has every kind.
  final Map<HighlightKind, HighlightStyle> highlights;

  /// The style of [kind].
  HighlightStyle highlightOf(HighlightKind kind) => highlights[kind]!;

  /// Vertical padding above and below each block.
  static const double blockPadding = 8;

  /// Widest text column in units of the body font size: about 65–75
  /// characters a line (T-111). Long lines on a wide window are hard to read.
  static const double maxColumnEms = 34;

  /// Widest text column, in logical pixels; the side padding is inside it.
  double get maxColumnWidth => settings.fontSize * maxColumnEms;

  /// Style of body text.
  TextStyle get body => TextStyle(
    fontFamily: settings.fontFamily,
    fontSize: settings.fontSize,
    height: settings.lineHeight,
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
