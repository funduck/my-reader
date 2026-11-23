// Ports the "Знаю" switch of the sheet reads, for tests that fake the lookup.
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// Splits on letters; the lemma is the lower-cased word.
class WordAnalyzer implements TextAnalyzer {
  @override
  List<SentenceSpan> sentences(String text) => [SentenceSpan(0, text.length)];

  @override
  List<TextToken> tokens(String text) => [
    for (final m in RegExp('[A-Za-z]+').allMatches(text))
      TextToken(m[0]!, m.start, m.end),
  ];

  @override
  String lemma(String word) => word.toLowerCase();
}

/// A word dictionary that knows nothing.
class NoLevels implements LevelDictionary {
  @override
  WordLevel levelOf(String lemma, {String? pos}) =>
      const WordLevel(CefrLevel.unknown);
}

/// Term storage and the ports `setTermStatusProvider` needs.
class TermSupport {
  /// The terms the switch reads and writes.
  final FakeTermRepository terms = FakeTermRepository();

  /// Provider overrides to add to the scope; [ids] is false for a test that
  /// wires its own id generator; [analyzer] replaces the one-sentence default.
  List<Override> overrides({bool ids = true, TextAnalyzer? analyzer}) => [
    termRepositoryProvider.overrideWithValue(terms),
    textAnalyzerProvider.overrideWithValue(analyzer ?? WordAnalyzer()),
    levelDictionaryProvider.overrideWithValue(NoLevels()),
    if (ids)
      idGeneratorProvider.overrideWithValue(SeqIdGenerator(prefix: 'term')),
  ];
}
