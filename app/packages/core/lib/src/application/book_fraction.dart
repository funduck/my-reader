import 'package:logging/logging.dart';

import '../domain/books/content_document.dart';
import '../domain/books/locator.dart';
import '../ports/book_format_adapter.dart';

final Logger _log = Logger('BookFraction');

/// Measures the chapters of [book]: the number of characters (UTF-16 units)
/// of the text of each chapter of `book.spine`, in spine order.
///
/// The text of a chapter is the text of its paragraphs, headings, quotes and
/// list items; images count as 0. Chapters are parsed one after another.
///
/// [shouldStop] is asked before each chapter; once it returns `true` the
/// measuring ends and the result is `null` (the caller closed the book). A
/// chapter that cannot be read makes the call throw, so that a partial
/// result is never mistaken for a whole one.
Future<List<int>?> measureChapterLengths(
  OpenedBook book, {
  bool Function()? shouldStop,
}) async {
  final lengths = <int>[];
  for (final ref in book.spine) {
    if (shouldStop?.call() ?? false) return null;
    final document = await book.chapter(ref);
    lengths.add(_blocksLength(document.blocks));
  }
  _log.fine('Measured ${lengths.length} chapters');
  return lengths;
}

/// Returns the fraction of the book that lies before [at], within 0..1.
///
/// With [chapterLengths] (see [measureChapterLengths]) the chapters weigh
/// what their text weighs: (characters of the chapters before the current
/// one + `progression` × length of the current one) / length of the book; a
/// book without text gives 0. Chapters past the end of [chapterLengths] have
/// no length.
///
/// Without [chapterLengths] all chapters weigh the same:
/// `(chapter index + progression) / chapterCount`; no chapters give 0.
double bookFraction(
  Locator at, {
  required int chapterCount,
  List<int>? chapterLengths,
}) {
  final index = at.chapter.index;
  final lengths = chapterLengths;
  final double raw;
  if (lengths == null) {
    raw = chapterCount <= 0 ? 0 : (index + at.progression) / chapterCount;
  } else {
    var total = 0;
    var before = 0;
    for (var i = 0; i < lengths.length; i++) {
      total += lengths[i];
      if (i < index) before += lengths[i];
    }
    final current = index >= 0 && index < lengths.length ? lengths[index] : 0;
    raw = total <= 0 ? 0 : (before + at.progression * current) / total;
  }
  return raw.isNaN ? 0 : raw.clamp(0.0, 1.0);
}

int _blocksLength(List<Block> blocks) {
  var sum = 0;
  for (final block in blocks) {
    sum += switch (block) {
      ParagraphBlock(:final inlines) => _inlinesLength(inlines),
      HeadingBlock(:final inlines) => _inlinesLength(inlines),
      QuoteBlock(blocks: final inner) => _blocksLength(inner),
      ListBlock(:final items) => items.fold(
        0,
        (total, item) => total + _inlinesLength(item),
      ),
      ImageBlock() => 0,
    };
  }
  return sum;
}

int _inlinesLength(List<Inline> inlines) {
  var sum = 0;
  for (final inline in inlines) {
    sum += switch (inline) {
      TextInline(:final text) => text.length,
      ItalicInline(:final children) => _inlinesLength(children),
      BoldInline(:final children) => _inlinesLength(children),
      LinkInline(:final children) => _inlinesLength(children),
    };
  }
  return sum;
}
