import 'package:meta/meta.dart';

import '../../../domain_books.dart';
import 'cefr_level.dart';

/// Kind of a cheat sheet entry.
enum CheatSheetItemKind {
  /// Single word.
  word,

  /// Multi-word expression, idiom or phrasal verb.
  expression;

  /// Parses [name]; returns [word] for null or unknown.
  static CheatSheetItemKind fromJson(Object? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return word;
  }

  /// JSON form: the enum name.
  String toJson() => name;
}

/// One word or expression in a cheat sheet.
@immutable
final class CheatSheetItem {
  /// Creates an item.
  const new({
    required this.text,
    required this.kind,
    this.level = CefrLevel.unknown,
    this.translation,
    this.example,
    this.zipf,
    this.lookupCount = 0,
    this.isProperName = false,
  });

  /// The word or expression.
  final String text;

  /// Word or expression.
  final CheatSheetItemKind kind;

  /// CEFR level.
  final CefrLevel level;

  /// Short translation or definition, if prepared.
  final String? translation;

  /// Short quote from the text around the item.
  final String? example;

  /// Zipf frequency of the lemma (higher is more frequent), if known.
  final double? zipf;

  /// How many times the user looked the word up (the `Term.lookupCount`);
  /// 0 — never. A word with a positive count is difficult whatever its level
  /// and frequency (T-121), unless the user marked it known.
  final int lookupCount;

  /// Whether the text shows a proper name (a capital letter inside a
  /// sentence and never in lower case). Such a word is difficult only by a
  /// positive [lookupCount].
  final bool isProperName;

  /// Copy with [lookupCount] replaced.
  CheatSheetItem copyWith({int? lookupCount}) => CheatSheetItem(
    text: text,
    kind: kind,
    level: level,
    translation: translation,
    example: example,
    zipf: zipf,
    lookupCount: lookupCount ?? this.lookupCount,
    isProperName: isProperName,
  );

  @override
  bool operator ==(Object other) =>
      other is CheatSheetItem &&
      other.text == text &&
      other.kind == kind &&
      other.level == level &&
      other.translation == translation &&
      other.example == example &&
      other.zipf == zipf &&
      other.lookupCount == lookupCount &&
      other.isProperName == isProperName;

  @override
  int get hashCode => Object.hash(
    text,
    kind,
    level,
    translation,
    example,
    zipf,
    lookupCount,
    isProperName,
  );
}

/// Cheat sheet for a text range.
@immutable
final class CheatSheet {
  /// Creates a cheat sheet.
  const new({required this.from, required this.to, required this.items});

  /// Start of the analysed range.
  final Locator from;

  /// End of the analysed range.
  final Locator to;

  /// Items to show.
  final List<CheatSheetItem> items;

  @override
  bool operator ==(Object other) {
    if (other is! CheatSheet ||
        other.from != from ||
        other.to != to ||
        other.items.length != items.length) {
      return false;
    }
    for (var i = 0; i < items.length; i++) {
      if (other.items[i] != items[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(from, to, Object.hashAll(items));
}
