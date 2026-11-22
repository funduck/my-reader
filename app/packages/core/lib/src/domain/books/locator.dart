import 'package:meta/meta.dart';

import 'chapter_ref.dart';
import 'ids.dart';
import 'text_quote.dart';

/// Renderer-independent position in a book (modelled on W3C Web Annotation
/// and Readium locators).
///
/// Restore order: [chapter] + [quote], then [progression], and [engineHint]
/// only as a renderer-specific shortcut.
@immutable
final class Locator {
  /// Creates a locator. [progression] must be within 0..1.
  const new({
    required this.book,
    required this.chapter,
    required this.progression,
    this.quote,
    this.engineHint,
  }) : assert(
         progression >= 0 && progression <= 1,
         'progression must be within 0..1',
       );

  /// Restores a locator from [toJson] output.
  factory fromJson(Map<String, Object?> json) {
    final quote = json['quote'];
    return Locator(
      book: BookId(json['book']! as String),
      chapter: ChapterRef.fromJson(json['chapter']! as Map<String, Object?>),
      progression: (json['progression']! as num).toDouble(),
      quote: quote == null
          ? null
          : TextQuote.fromJson(quote as Map<String, Object?>),
      engineHint: json['engineHint'] as String?,
    );
  }

  /// Book the position belongs to.
  final BookId book;

  /// Chapter the position is in.
  final ChapterRef chapter;

  /// Fraction of the chapter before the position, 0..1.
  final double progression;

  /// Exact text at the position with context, if known.
  final TextQuote? quote;

  /// Opaque cache of a fast position for one renderer; may be stale.
  final String? engineHint;

  /// Returns a copy with the given fields replaced.
  ///
  /// [quote] and [engineHint] cannot be reset to null with this method; build
  /// a new [Locator] for that.
  Locator copyWith({
    BookId? book,
    ChapterRef? chapter,
    double? progression,
    TextQuote? quote,
    String? engineHint,
  }) => Locator(
    book: book ?? this.book,
    chapter: chapter ?? this.chapter,
    progression: progression ?? this.progression,
    quote: quote ?? this.quote,
    engineHint: engineHint ?? this.engineHint,
  );

  /// JSON form for storage; null fields are omitted.
  Map<String, Object?> toJson() => {
    'book': book.value,
    'chapter': chapter.toJson(),
    'progression': progression,
    if (quote != null) 'quote': quote!.toJson(),
    if (engineHint != null) 'engineHint': engineHint,
  };

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

  @override
  String toString() => 'Locator($book, $chapter, $progression)';
}
