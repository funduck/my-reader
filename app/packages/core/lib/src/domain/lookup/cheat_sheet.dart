import 'package:meta/meta.dart';

import 'cefr_level.dart';
import 'locator_stub.dart';

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
  });

  /// The word or expression.
  final String text;

  /// Word or expression.
  final CheatSheetItemKind kind;

  /// CEFR level.
  final CefrLevel level;

  /// Short translation or definition, if prepared.
  final String? translation;

  /// Sentence from the text with the item.
  final String? example;

  @override
  bool operator ==(Object other) =>
      other is CheatSheetItem &&
      other.text == text &&
      other.kind == kind &&
      other.level == level &&
      other.translation == translation &&
      other.example == example;

  @override
  int get hashCode => Object.hash(text, kind, level, translation, example);
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
