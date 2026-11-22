import 'package:meta/meta.dart';

import '../../domain/books/chapter_ref.dart';
import '../../domain/books/content_document.dart';
import '../../domain/books/ids.dart';
import '../../domain/books/locator.dart';
import '../../domain/books/text_quote.dart';
import '../../domain/profile/cheat_sheet_scope.dart';
import '../../ports/book_format_adapter.dart';

/// Number of words in one conventional page (S-2).
const wordsPerPage = 300;

/// Separator between paragraphs in [CheatSheetRange.text] and in the chapter
/// text that offsets and progressions are measured over.
const paragraphSeparator = '\n\n';

/// Longest `exact` part of the quotes in the range locators, in UTF-16 units.
const _quoteLength = 30;

/// Piece of a book chosen for a cheat sheet: where it starts and ends and
/// its text.
@immutable
final class CheatSheetRange {
  /// Creates a range.
  const new({
    required this.start,
    required this.end,
    required this.text,
    required this.wordCount,
  });

  /// Start of the first paragraph of the range.
  final Locator start;

  /// End of the last paragraph of the range (the position right after its
  /// last character); may be in a later chapter than [start].
  final Locator end;

  /// Text of the range: paragraphs joined by [paragraphSeparator], chapters
  /// joined the same way.
  final String text;

  /// Number of words in [text], counted by [countWords].
  final int wordCount;

  @override
  bool operator ==(Object other) =>
      other is CheatSheetRange &&
      other.start == start &&
      other.end == end &&
      other.text == text &&
      other.wordCount == wordCount;

  @override
  int get hashCode => Object.hash(start, end, text, wordCount);

  @override
  String toString() => 'CheatSheetRange($start .. $end, $wordCount words)';
}

final RegExp _word = RegExp(
  r"[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*",
  unicode: true,
);

/// Counts words in [text].
///
/// A word is a run of Unicode letters and digits; an apostrophe (`'`, `’`) or
/// hyphen between two such runs joins them into one word ("don't",
/// "well-known" are one word each). Other characters only separate words.
int countWords(String text) => _word.allMatches(text).length;

/// Chooses the piece of [book] that a cheat sheet analyses (S-1, S-2).
///
/// The piece starts at the beginning of the paragraph that contains [from]
/// and ends at the end of a paragraph:
///
/// - [CheatSheetPages]: paragraphs are taken one after another, continuing
///   into the next chapters, until the total reaches `pages * wordsPerPage`
///   words. The paragraph that reaches the budget is included whole, so the
///   piece may be longer than the budget but always ends on a paragraph.
///   The end of the book stops the piece.
/// - [CheatSheetChapter]: up to the end of the chapter of [from].
///
/// A paragraph is a paragraph, heading, quoted block or list item of the
/// chapter; images and blocks with only whitespace are skipped. Chapter text
/// is its paragraphs joined by [paragraphSeparator]. [from] is placed by
/// chapter and `progression` (the fraction of that text before the position);
/// the quote of [from] is not used. Offsets are UTF-16.
///
/// Locators of the result carry chapter, progression and a [TextQuote] of the
/// first (start) or last (end) up to 30 characters of the paragraph.
///
/// Returns null when [from] names a chapter that is not in `book.spine`, or
/// when there is no text at or after the paragraph (for [CheatSheetChapter]:
/// in the chapter itself).
Future<CheatSheetRange?> selectCheatSheetRange(
  OpenedBook book, {
  required Locator from,
  required CheatSheetScope scope,
}) async {
  final spine = book.spine;
  final startIndex = _spineIndex(spine, from.chapter);
  if (startIndex < 0) return null;
  final budget = switch (scope) {
    CheatSheetPages(:final pages) => pages * wordsPerPage,
    CheatSheetChapter() => null,
  };

  Locator? start;
  Locator? end;
  final texts = <String>[];
  var words = 0;
  for (var i = startIndex; i < spine.length; i++) {
    final chapter = _Chapter.parse(spine[i], await book.chapter(spine[i]));
    final first = i == startIndex ? chapter.unitAt(from.progression) : 0;
    var reached = false;
    for (var j = first; j < chapter.units.length && !reached; j++) {
      final unit = chapter.units[j];
      start ??= chapter.locator(from.book, unit, head: true);
      end = chapter.locator(from.book, unit, head: false);
      texts.add(unit.text);
      words += countWords(unit.text);
      reached = budget != null && words >= budget;
    }
    if (reached || budget == null) break;
  }
  if (start == null || end == null) return null;
  return CheatSheetRange(
    start: start,
    end: end,
    text: texts.join(paragraphSeparator),
    wordCount: words,
  );
}

int _spineIndex(List<ChapterRef> spine, ChapterRef ref) {
  final exact = spine.indexOf(ref);
  return exact >= 0 ? exact : spine.indexWhere((c) => c.href == ref.href);
}

/// One paragraph with its `[start, end)` span in the chapter text.
final class _Unit {
  const new(this.text, this.start) : end = start + text.length;

  final String text;
  final int start;
  final int end;
}

/// Parsed chapter: paragraphs and the text they make up.
final class _Chapter {
  const new(this.ref, this.units, this.text);

  factory parse(ChapterRef ref, ContentDocument document) {
    final texts = <String>[];
    _collect(document.blocks, texts);
    final units = <_Unit>[];
    var offset = 0;
    for (final text in texts) {
      units.add(_Unit(text, offset));
      offset += text.length + paragraphSeparator.length;
    }
    return _Chapter(ref, units, texts.join(paragraphSeparator));
  }

  final ChapterRef ref;
  final List<_Unit> units;
  final String text;

  /// Index of the paragraph holding the position [progression]; the gap after
  /// a paragraph belongs to it. 0 for an empty chapter.
  int unitAt(double progression) {
    final offset = (progression * text.length).floor();
    var found = 0;
    for (var i = 0; i < units.length; i++) {
      if (units[i].start > offset) break;
      found = i;
    }
    return found;
  }

  /// Locator at the start (if [head]) or end of [unit]. The quote is the first
  /// (if [head]) or last up to [_quoteLength] characters of [unit].
  Locator locator(BookId book, _Unit unit, {required bool head}) {
    var from = head ? unit.start : unit.end - _quoteLength;
    var to = head ? unit.start + _quoteLength : unit.end;
    if (from < unit.start) from = unit.start;
    if (to > unit.end) to = unit.end;
    // Do not split a surrogate pair and do not begin or end on whitespace.
    if (to < unit.end && _isHigh(text.codeUnitAt(to - 1))) to--;
    if (from > unit.start && _isLow(text.codeUnitAt(from))) from++;
    while (to > from && _isSpace(text.codeUnitAt(to - 1))) {
      to--;
    }
    while (from < to && _isSpace(text.codeUnitAt(from))) {
      from++;
    }
    return Locator(
      book: book,
      chapter: ref,
      progression: (head ? unit.start : unit.end) / text.length,
      quote: from < to ? TextQuote.fromText(text, from, to) : null,
    );
  }
}

bool _isHigh(int u) => u >= 0xD800 && u <= 0xDBFF;
bool _isLow(int u) => u >= 0xDC00 && u <= 0xDFFF;
bool _isSpace(int u) => u == 0x20 || (u >= 0x09 && u <= 0x0D) || u == 0xA0;

void _collect(List<Block> blocks, List<String> out) {
  for (final block in blocks) {
    switch (block) {
      case ParagraphBlock(:final inlines):
      case HeadingBlock(:final inlines):
        _add(inlines, out);
      case QuoteBlock(blocks: final inner):
        _collect(inner, out);
      case ListBlock(:final items):
        for (final item in items) {
          _add(item, out);
        }
      case ImageBlock():
        break;
    }
  }
}

void _add(List<Inline> inlines, List<String> out) {
  final text = _plain(inlines).trim();
  if (text.isNotEmpty) out.add(text);
}

String _plain(List<Inline> inlines) {
  final buffer = StringBuffer();
  for (final inline in inlines) {
    switch (inline) {
      case TextInline(:final text):
        buffer.write(text);
      case ItalicInline(:final children):
      case BoldInline(:final children):
      case LinkInline(:final children):
        buffer.write(_plain(children));
    }
  }
  return buffer.toString();
}
