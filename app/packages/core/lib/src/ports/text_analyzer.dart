import 'package:meta/meta.dart';

/// A sentence in a text, as a half-open range of UTF-16 offsets.
@immutable
final class SentenceSpan {
  /// Creates a span of `text.substring(start, end)`.
  const new(this.start, this.end);

  /// Offset of the first character.
  final int start;

  /// Offset after the last character.
  final int end;

  @override
  bool operator ==(Object other) =>
      other is SentenceSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// A word in a text with its position, as a half-open range of UTF-16 offsets.
@immutable
final class TextToken {
  /// Creates a token.
  const new(this.text, this.start, this.end);

  /// The word as written in the text.
  final String text;

  /// Offset of the first character.
  final int start;

  /// Offset after the last character.
  final int end;

  @override
  bool operator ==(Object other) =>
      other is TextToken &&
      other.text == text &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(text, start, end);
}

/// Splits text and normalizes words; synchronous and offline.
abstract interface class TextAnalyzer {
  /// Splits [text] into sentences, in order, with offsets into [text].
  List<SentenceSpan> sentences(String text);

  /// Splits [text] into word tokens, in order, with offsets into [text].
  List<TextToken> tokens(String text);

  /// Returns the base form of [word] (`running` -> `run`), lower case.
  ///
  /// Returns the lower-cased word itself if no base form is known.
  String lemma(String word);
}
