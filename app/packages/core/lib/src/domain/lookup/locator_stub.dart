/// TEMPORARY stub of the books domain types from Architecture-app.md 3.1.
///
/// Replace with an import of `domain_books.dart` once T-003 is merged,
/// then delete this file.
library;

import 'package:meta/meta.dart';

/// Identifier of a book in the library.
@immutable
final class BookId {
  /// Creates an id from its string [value].
  const new(this.value);

  /// Raw id string.
  final String value;

  @override
  bool operator ==(Object other) => other is BookId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Neutral reference to a chapter: href inside the book plus spine index.
@immutable
final class ChapterRef {
  /// Creates a reference.
  const new({required this.href, required this.index});

  /// Resource path inside the book.
  final String href;

  /// Zero-based spine index.
  final int index;

  @override
  bool operator ==(Object other) =>
      other is ChapterRef && other.href == href && other.index == index;

  @override
  int get hashCode => Object.hash(href, index);
}

/// Exact quote with up to 30 characters of context on each side.
@immutable
final class TextQuote {
  /// Creates a quote.
  const new({required this.exact, this.prefix = '', this.suffix = ''});

  /// The quoted text.
  final String exact;

  /// Text right before [exact].
  final String prefix;

  /// Text right after [exact].
  final String suffix;

  @override
  bool operator ==(Object other) =>
      other is TextQuote &&
      other.exact == exact &&
      other.prefix == prefix &&
      other.suffix == suffix;

  @override
  int get hashCode => Object.hash(exact, prefix, suffix);
}

/// Renderer-independent position in a book.
@immutable
final class Locator {
  /// Creates a locator.
  const new({
    required this.book,
    required this.chapter,
    required this.progression,
    this.quote,
    this.engineHint,
  });

  /// Book this position belongs to.
  final BookId book;

  /// Chapter within the book.
  final ChapterRef chapter;

  /// Position inside the chapter, 0..1.
  final double progression;

  /// Exact quote at the position, if known.
  final TextQuote? quote;

  /// Opaque renderer-specific cache.
  final String? engineHint;

  @override
  bool operator ==(Object other) =>
      other is Locator &&
      other.book == book &&
      other.chapter == chapter &&
      other.progression == progression &&
      other.quote == quote &&
      other.engineHint == engineHint;

  @override
  int get hashCode =>
      Object.hash(book, chapter, progression, quote, engineHint);
}
