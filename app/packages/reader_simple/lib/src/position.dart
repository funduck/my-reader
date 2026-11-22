import 'package:core/domain_books.dart';
import 'package:flutter/foundation.dart';

/// Plain text of [inlines] as the reader draws it.
String inlinesText(List<Inline> inlines) => inlines.map(_inlineText).join();

String _inlineText(Inline inline) => switch (inline) {
  TextInline(:final text) => text,
  ItalicInline(:final children) => inlinesText(children),
  BoldInline(:final children) => inlinesText(children),
  LinkInline(:final children) => inlinesText(children),
};

/// Plain text of [block]. For a paragraph or a heading it is exactly the text
/// of the one text widget that draws the block; compound blocks join their
/// parts with a newline.
String blockText(Block block) => switch (block) {
  ParagraphBlock(:final inlines) => inlinesText(inlines),
  HeadingBlock(:final inlines) => inlinesText(inlines),
  QuoteBlock(:final blocks) => blocks.map(blockText).join('\n'),
  ListBlock(:final items) => items.map(inlinesText).join('\n'),
  ImageBlock(:final alt) => alt ?? '',
};

/// A place in a chapter: a block and a character offset in its text.
@immutable
final class BlockPosition {
  /// Creates a position.
  const new(this.block, this.offset);

  /// Index into `ContentDocument.blocks`.
  final int block;

  /// UTF-16 offset in `blockText` of the block.
  final int offset;

  @override
  bool operator ==(Object other) =>
      other is BlockPosition && other.block == block && other.offset == offset;

  @override
  int get hashCode => Object.hash(BlockPosition, block, offset);

  @override
  String toString() => 'BlockPosition($block, $offset)';
}

final RegExp _whitespace = RegExp(r'\s');

bool _isSpace(String text, int i) => _whitespace.hasMatch(text[i]);

/// The text of one chapter, with conversions between a [BlockPosition],
/// a `progression` and a `TextQuote`.
///
/// The chapter text is the block texts joined by `\n`; `progression` is the
/// fraction of that text before the position.
class ChapterText {
  /// Builds the text of [document].
  factory of(ContentDocument document) {
    final texts = [for (final b in document.blocks) blockText(b)];
    final starts = <int>[];
    var at = 0;
    for (final t in texts) {
      starts.add(at);
      at += t.length + 1;
    }
    return ChapterText._(texts, starts, texts.join('\n'));
  }

  new _(this._blocks, this._starts, this.text);

  final List<String> _blocks;
  final List<int> _starts;

  /// All block texts joined by `\n`.
  final String text;

  // Whitespace-collapsed `text` and, for each of its characters, the index of
  // the same character in `text`. Built on first use.
  late final ({String flat, List<int> origin}) _collapsed = _collapse();

  /// Number of blocks.
  int get blockCount => _blocks.length;

  /// Text of block [block].
  String blockAt(int block) => _blocks[block];

  /// Index in [text] of [position].
  int indexOf(BlockPosition position) =>
      _starts[position.block] + position.offset;

  /// Fraction of the text before [position], 0..1.
  double progressionOf(BlockPosition position) {
    if (text.isEmpty) return 0;
    return (indexOf(position) / text.length).clamp(0.0, 1.0);
  }

  /// The position at [progression]; 1 is the start of the last block.
  BlockPosition fromProgression(double progression) {
    if (_blocks.isEmpty) return const BlockPosition(0, 0);
    if (progression >= 1) return BlockPosition(_blocks.length - 1, 0);
    if (text.isEmpty) return const BlockPosition(0, 0);
    return _positionAt((progression * text.length).round());
  }

  BlockPosition _positionAt(int index) {
    var lo = 0;
    var hi = _starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_starts[mid] <= index) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return BlockPosition(
      lo,
      (index - _starts[lo]).clamp(0, _blocks[lo].length),
    );
  }

  /// Whether [quote] is found exactly at [position]: the text there (leading
  /// whitespace skipped) is `quote.exact` and its surroundings are the quote's
  /// prefix and suffix, up to the ends of the chapter.
  bool confirms(BlockPosition position, TextQuote quote) {
    final exact = quote.exact;
    if (exact.isEmpty) return false;
    var start = indexOf(position);
    while (start < text.length && _isSpace(text, start)) {
      start++;
    }
    final (:flat, :origin) = _collapsed;
    final from = _lowerBound(origin, start);
    if (from >= origin.length || origin[from] != start) return false;
    if (!flat.startsWith(exact, from)) return false;
    final before = flat.substring(
      from < quote.prefix.length ? 0 : from - quote.prefix.length,
      from,
    );
    final afterFrom = from + exact.length;
    final after = flat.substring(
      afterFrom,
      afterFrom + quote.suffix.length > flat.length
          ? flat.length
          : afterFrom + quote.suffix.length,
    );
    return quote.prefix.endsWith(before) && quote.suffix.startsWith(after);
  }

  static int _lowerBound(List<int> sorted, int value) {
    var lo = 0;
    var hi = sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (sorted[mid] < value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Finds [quote] in the chapter; `null` if it is absent or ambiguous.
  ///
  /// Of several matches of `exact` the one whose surroundings agree most with
  /// the quote's prefix and suffix wins; equal scores are decided by the
  /// distance to [progression]. Several matches that all disagree with the
  /// surroundings are ambiguous.
  BlockPosition? find(TextQuote quote, double progression) {
    final exact = quote.exact;
    if (exact.isEmpty) return null;
    final (:flat, :origin) = _collapsed;
    final hits = <int>[];
    for (var i = flat.indexOf(exact); i >= 0; i = flat.indexOf(exact, i + 1)) {
      hits.add(i);
    }
    if (hits.isEmpty) return null;
    final target = progression * text.length;
    var best = hits.first;
    var bestScore = -1;
    var bestDistance = double.infinity;
    for (final i in hits) {
      final beforeFrom = i < quote.prefix.length ? 0 : i - quote.prefix.length;
      final afterFrom = i + exact.length;
      final afterTo = afterFrom + quote.suffix.length;
      final score =
          _commonSuffix(flat.substring(beforeFrom, i), quote.prefix) +
          _commonPrefix(
            flat.substring(
              afterFrom,
              afterTo > flat.length ? flat.length : afterTo,
            ),
            quote.suffix,
          );
      final distance = (origin[i] - target).abs();
      if (score > bestScore ||
          (score == bestScore && distance < bestDistance)) {
        best = i;
        bestScore = score;
        bestDistance = distance;
      }
    }
    final hasContext = quote.prefix.isNotEmpty || quote.suffix.isNotEmpty;
    if (hits.length > 1 && hasContext && bestScore == 0) return null;
    return _positionAt(origin[best]);
  }

  /// Where [quote] lies at [position] as a range of [text]: the first
  /// non-space character at or after [position] to the end of `quote.exact`.
  /// `null` if the text there is not the quote.
  ({int start, int end})? rangeOf(BlockPosition position, TextQuote quote) {
    var i = indexOf(position);
    while (i < text.length && _isSpace(text, i)) {
      i++;
    }
    final start = i;
    final exact = quote.exact;
    if (exact.isEmpty) return null;
    for (var j = 0; j < exact.length; j++) {
      if (i >= text.length) return null;
      if (exact[j] == ' ') {
        if (!_isSpace(text, i)) return null;
        while (i < text.length && _isSpace(text, i)) {
          i++;
        }
      } else {
        if (text[i] != exact[j]) return null;
        i++;
      }
    }
    return (start: start, end: i);
  }

  /// Where [locator] lies in chapter [chapter], by its hint or its quote only;
  /// `null` when neither finds it (the progression alone is not precise
  /// enough to mark text).
  ({int start, int end})? rangeOfLocator(Locator locator, int chapter) {
    final quote = locator.quote;
    if (quote == null || quote.exact.isEmpty) return null;
    final hinted = decodeHint(locator.engineHint, chapter, this);
    final at = hinted != null && confirms(hinted, quote)
        ? hinted
        : find(quote, locator.progression);
    return at == null ? null : rangeOf(at, quote);
  }

  /// Splits the chapter range `[start, end)` into ranges inside blocks:
  /// block index to `(start, end)` offsets in the block text.
  Map<int, List<(int, int)>> blockRanges(int start, int end) {
    final result = <int, List<(int, int)>>{};
    if (_blocks.isEmpty || end <= start) return result;
    for (var b = _positionAt(start).block; b < _blocks.length; b++) {
      final blockStart = _starts[b];
      if (blockStart >= end) break;
      final lo = start > blockStart ? start : blockStart;
      final blockEnd = blockStart + _blocks[b].length;
      final hi = end < blockEnd ? end : blockEnd;
      if (hi > lo) {
        (result[b] ??= []).add((lo - blockStart, hi - blockStart));
      }
    }
    return result;
  }

  ({String flat, List<int> origin}) _collapse() {
    final flat = StringBuffer();
    final origin = <int>[];
    var inSpace = false;
    for (var i = 0; i < text.length; i++) {
      if (_isSpace(text, i)) {
        if (!inSpace) {
          flat.write(' ');
          origin.add(i);
        }
        inSpace = true;
      } else {
        flat.write(text[i]);
        origin.add(i);
        inSpace = false;
      }
    }
    return (flat: flat.toString(), origin: origin);
  }

  static int _commonSuffix(String a, String b) {
    var n = 0;
    while (n < a.length &&
        n < b.length &&
        a.codeUnitAt(a.length - 1 - n) == b.codeUnitAt(b.length - 1 - n)) {
      n++;
    }
    return n;
  }

  static int _commonPrefix(String a, String b) {
    var n = 0;
    while (n < a.length && n < b.length && a.codeUnitAt(n) == b.codeUnitAt(n)) {
      n++;
    }
    return n;
  }

  /// Builds the quote of the text that starts at [position] and runs to
  /// [lineEnd] (an offset in the block text) but not over [maxLength]
  /// characters. `null` when only whitespace is there.
  TextQuote? quoteAt(
    BlockPosition position, {
    int? lineEnd,
    int maxLength = 80,
  }) {
    var start = indexOf(position);
    while (start < text.length && _isSpace(text, start)) {
      start++;
    }
    var end = lineEnd == null
        ? start + maxLength
        : _starts[position.block] + lineEnd;
    if (end > start + maxLength) end = start + maxLength;
    if (end > text.length) end = text.length;
    while (end > start && _isSpace(text, end - 1)) {
      end--;
    }
    if (end <= start) return null;
    return TextQuote.fromText(text, start, end);
  }
}

/// The `Locator.engineHint` of [position] in chapter [chapter].
///
/// Format: `simple:1:<chapter index>:<block>:<offset>`.
String encodeHint(int chapter, BlockPosition position) =>
    'simple:1:$chapter:${position.block}:${position.offset}';

/// The position in [hint] if it is well formed, is for [chapter] and lies
/// inside [text]; otherwise `null`.
BlockPosition? decodeHint(String? hint, int chapter, ChapterText text) {
  if (hint == null) return null;
  final parts = hint.split(':');
  if (parts.length != 5 || parts[0] != 'simple' || parts[1] != '1') {
    return null;
  }
  final c = int.tryParse(parts[2]);
  final block = int.tryParse(parts[3]);
  final offset = int.tryParse(parts[4]);
  if (c != chapter || block == null || offset == null) return null;
  if (block < 0 || block >= text.blockCount) return null;
  if (offset < 0 || offset > text.blockAt(block).length) return null;
  return BlockPosition(block, offset);
}

/// Where to show [locator] in chapter [chapter]: the hint if it is intact,
/// then the quote, then the progression.
BlockPosition resolveLocator({
  required Locator locator,
  required int chapter,
  required ChapterText text,
}) {
  final quote = locator.quote;
  final hinted = decodeHint(locator.engineHint, chapter, text);
  if (hinted != null &&
      (quote == null || quote.exact.isEmpty || text.confirms(hinted, quote))) {
    return hinted;
  }
  if (quote != null) {
    final found = text.find(quote, locator.progression);
    if (found != null) return found;
  }
  return text.fromProgression(locator.progression);
}
