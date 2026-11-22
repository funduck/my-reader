import 'package:meta/meta.dart';

import '../domain/lookup/cefr_level.dart';

/// Level of a word: the answer of [LevelDictionary.levelOf].
@immutable
final class WordLevel {
  /// Creates a result.
  const new(this.level, {this.estimated = false, this.zipf});

  /// CEFR level; [CefrLevel.unknown] if the dictionary has no data.
  final CefrLevel level;

  /// Whether the level was derived from frequency rather than a CEFR list.
  final bool estimated;

  /// Zipf frequency of the word, or null if unknown.
  final double? zipf;

  @override
  bool operator ==(Object other) =>
      other is WordLevel &&
      other.level == level &&
      other.estimated == estimated &&
      other.zipf == zipf;

  @override
  int get hashCode => Object.hash(level, estimated, zipf);
}

/// CEFR level of a word (S-3, T-4); synchronous, reads local packs.
abstract interface class LevelDictionary {
  /// Returns the level of [lemma], optionally narrowed by part of speech [pos].
  ///
  /// An unknown word yields `WordLevel(CefrLevel.unknown)`; never throws.
  WordLevel levelOf(String lemma, {String? pos});
}
