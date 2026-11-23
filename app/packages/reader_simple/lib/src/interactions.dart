import 'package:core/ports.dart';

/// One text widget of a block, as the engine needs to know it to turn a tap
/// or a selection into a position.
final class TextTarget {
  /// Creates a target: the text widget of block [block] that shows [text].
  const new({required this.block, required this.base, required this.text});

  /// Index into `ContentDocument.blocks`.
  final int block;

  /// Offset of [text] in the block text (`blockText`); not zero for the
  /// second paragraph of a quote or the second item of a list.
  final int base;

  /// The text of the widget, exactly as it is drawn.
  final String text;
}

/// What the text widgets of a block report to the engine.
abstract interface class TextInteractions {
  /// A single tap landed at [offset] in `target.text`.
  void wordTapped(TextTarget target, int offset);

  /// The user chose "Translate" with `target.text.substring(start, end)`
  /// selected.
  void textSelected(TextTarget target, int start, int end);

  /// The text of [target] got a non-empty selection ([active]) or lost it.
  ///
  /// A tap while any text is selected only clears the selection and is not a
  /// `ViewTapped`.
  void selectionChanged(TextTarget target, {required bool active});
}

final RegExp _word = RegExp(
  r"[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*",
  unicode: true,
);

/// The word of [text] under the caret [offset] as `[start, end)`, or `null`.
///
/// The caret of a tap sits on the nearest edge between two characters, so a
/// tap on the right half of the last letter gives the end of the word: the
/// character before the caret is tried too. A word is letters and digits,
/// joined by an inner apostrophe or hyphen; punctuation is not part of it.
(int, int)? wordRangeAt(String text, int offset) {
  for (final at in [offset, offset - 1]) {
    for (final m in _word.allMatches(text)) {
      if (at >= m.start && at < m.end) return (m.start, m.end);
    }
  }
  return null;
}

/// The sentence of [text] that holds `text.substring(start, end)`, trimmed.
///
/// [text] is one paragraph (one text widget), so a sentence never continues
/// into the neighbouring paragraph. A selection over several sentences gives
/// all of them, from the one with [start] to the one with the last character.
/// Without a sentence from [analyzer] the whole [text] is returned.
String sentenceAround(TextAnalyzer analyzer, String text, int start, int end) {
  SentenceSpan? first;
  SentenceSpan? last;
  final tail = end > start ? end - 1 : start;
  for (final s in analyzer.sentences(text)) {
    if (s.start <= start && start < s.end) first ??= s;
    if (s.start <= tail && tail < s.end) last = s;
  }
  if (first == null) return text.trim();
  final to = (last ?? first).end;
  final lo = first.start.clamp(0, text.length);
  return text.substring(lo, to.clamp(lo, text.length)).trim();
}
