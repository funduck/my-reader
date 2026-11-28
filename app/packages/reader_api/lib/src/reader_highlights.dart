import 'package:core/domain_books.dart';
import 'package:flutter/foundation.dart';

/// How long the engine pulses a `recent` highlight (T-124).
///
/// The engine animates [HighlightKind.recent] itself for this long from the
/// moment the set of `recent` marks changes, and takes the mark off at the
/// end. The caller drops `recent` from its highlights after the same time,
/// so the two agree without the engine reporting the end.
const Duration recentPulseDuration = Duration(milliseconds: 2500);

/// What a highlighted piece of text means (B-019).
///
/// The declaration order is the priority: where several kinds meet on one
/// word, the engine draws the kind that comes first.
enum HighlightKind {
  /// The word of the open translation and the place of a history link.
  focus,

  /// The word that was just translated: the engine pulses it for
  /// [recentPulseDuration] and then draws nothing (T-124).
  recent,

  /// A word the reader has looked up before.
  lookedUp,

  /// A word that was in the last cheat sheet.
  cheatSheet,

  /// A word that is hard for the reader's level.
  difficult,
}

/// Everything the engine marks in the text: places and words by
/// [HighlightKind].
///
/// [ranges] are places given as [Locator]s (they need a `quote`); [words] are
/// lemmas (lower case, as `TextAnalyzer.lemma` returns them) that the engine
/// looks for in the chapter on its own. The maps are not changed after
/// construction.
@immutable
final class ReaderHighlights {
  /// Creates highlights; both maps may omit kinds.
  const new({this.ranges = const {}, this.words = const {}});

  /// No highlights: passed to `ReaderEngine.highlight` it clears all.
  static const ReaderHighlights none = ReaderHighlights();

  /// Places by kind.
  final Map<HighlightKind, List<Locator>> ranges;

  /// Lemmas by kind: every form of such a word is marked.
  final Map<HighlightKind, Set<String>> words;

  /// Whether nothing is marked: no kind has a place or a word.
  bool get isEmpty =>
      ranges.values.every((r) => r.isEmpty) &&
      words.values.every((w) => w.isEmpty);

  @override
  bool operator ==(Object other) =>
      other is ReaderHighlights &&
      _sameMap(ranges, other.ranges, listEquals<Locator>) &&
      _sameMap(words, other.words, setEquals<String>);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered([
      for (final e in ranges.entries)
        Object.hash(e.key, Object.hashAll(e.value)),
    ]),
    Object.hashAllUnordered([
      for (final e in words.entries)
        Object.hash(e.key, Object.hashAllUnordered(e.value)),
    ]),
  );

  @override
  String toString() => 'ReaderHighlights(ranges: $ranges, words: $words)';
}

bool _sameMap<V>(
  Map<HighlightKind, V> a,
  Map<HighlightKind, V> b,
  bool Function(V, V) same,
) {
  if (a.length != b.length) return false;
  for (final MapEntry(:key, :value) in a.entries) {
    final other = b[key];
    if (other == null || !same(value, other)) return false;
  }
  return true;
}
