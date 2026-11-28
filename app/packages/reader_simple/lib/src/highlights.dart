import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:reader_api/reader_api.dart';

import 'position.dart';

/// A marked piece of a block: `[start, end)` offsets in the block text.
typedef BlockHighlight = ({int start, int end, HighlightKind kind});

/// What is drawn over each piece of a block: `[start, end)` offsets of the
/// pieces in order, none overlapping, and the kind that wins on each.
///
/// The text is cut at the boundaries of all [highlights]; a piece takes the
/// kind with the smallest index of those that cover it (the priority of
/// [HighlightKind]). Neighbouring pieces of one kind are one piece, so a
/// phrase marked by two overlapping ranges of one kind is a single piece,
/// while words with a space between them stay apart.
List<BlockHighlight> winningRanges(List<BlockHighlight> highlights) {
  if (highlights.isEmpty) return const [];
  final cuts = <int>{
    for (final h in highlights)
      if (h.start < h.end) ...[h.start, h.end],
  }.toList()..sort();
  final result = <BlockHighlight>[];
  for (var i = 0; i + 1 < cuts.length; i++) {
    final (from, to) = (cuts[i], cuts[i + 1]);
    HighlightKind? best;
    for (final h in highlights) {
      if (h.start <= from && to <= h.end) {
        if (best == null || h.kind.index < best.index) best = h.kind;
      }
    }
    if (best == null) continue;
    if (result.isNotEmpty &&
        result.last.end == from &&
        result.last.kind == best) {
      result[result.length - 1] = (
        start: result.last.start,
        end: to,
        kind: best,
      );
    } else {
      result.add((start: from, end: to, kind: best));
    }
  }
  return result;
}

/// The words of the blocks of one chapter with their lemmas.
///
/// A block is tokenized and lemmatized the first time it is asked for, and
/// never again for this chapter: changing the highlights does not repeat the
/// work.
class ChapterLemmas {
  /// Creates an index over [text], using the given analyzer.
  new(this.text, this._analyzer);

  /// The chapter text the blocks come from.
  final ChapterText text;
  final TextAnalyzer _analyzer;
  final Map<int, List<({int start, int end, String lemma})>> _blocks = {};

  /// The words of block [block] in order.
  List<({int start, int end, String lemma})> of(int block) =>
      _blocks[block] ??= [
        for (final token in _analyzer.tokens(text.blockAt(block)))
          (
            start: token.start,
            end: token.end,
            lemma: _analyzer.lemma(token.text),
          ),
      ];
}

/// What [ReaderHighlights] mark in one chapter, by block.
///
/// The places are resolved at once; the words are looked up in a block when
/// the block is drawn ([forBlock]), so the cost of a change does not depend
/// on the length of the chapter.
class ChapterHighlights {
  /// Resolves the places of [highlights] in [text], the chapter with index
  /// [chapter]; words are looked up in [lemmas].
  factory resolve(
    ReaderHighlights highlights,
    ChapterText text,
    int chapter,
    ChapterLemmas lemmas,
  ) {
    final ranges = <int, List<BlockHighlight>>{};
    for (final kind in HighlightKind.values) {
      for (final locator in highlights.ranges[kind] ?? const <Locator>[]) {
        if (locator.chapter.index != chapter) continue;
        final range = text.rangeOfLocator(locator, chapter);
        if (range == null) continue;
        text.blockRanges(range.start, range.end).forEach((block, parts) {
          (ranges[block] ??= []).addAll([
            for (final (start, end) in parts)
              (start: start, end: end, kind: kind),
          ]);
        });
      }
    }
    return ChapterHighlights._(highlights, text, ranges, [
      for (final kind in HighlightKind.values)
        if (highlights.words[kind] case final words? when words.isNotEmpty)
          (kind, words),
    ], lemmas);
  }

  new _(this.source, this.text, this._ranges, this._words, this._lemmas);

  /// The highlights this was resolved from.
  final ReaderHighlights source;

  /// The chapter text it was resolved in.
  final ChapterText text;

  final Map<int, List<BlockHighlight>> _ranges;

  // Kinds that have words, in priority order.
  final List<(HighlightKind, Set<String>)> _words;
  final ChapterLemmas _lemmas;
  final Map<int, List<BlockHighlight>> _blocks = {};

  /// Everything marked in block [block]; the same list every time.
  List<BlockHighlight> forBlock(int block) =>
      _blocks[block] ??= _compute(block);

  List<BlockHighlight> _compute(int block) {
    final result = [...?_ranges[block]];
    if (_words.isNotEmpty) {
      for (final word in _lemmas.of(block)) {
        for (final (kind, lemmas) in _words) {
          if (lemmas.contains(word.lemma)) {
            result.add((start: word.start, end: word.end, kind: kind));
            break;
          }
        }
      }
    }
    return result.isEmpty ? const [] : List.unmodifiable(result);
  }
}
