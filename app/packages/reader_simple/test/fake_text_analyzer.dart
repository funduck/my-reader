import 'package:core/ports.dart';

/// A [TextAnalyzer] for tests: a sentence ends at `.`, `!` or `?`, and the
/// whitespace after the mark belongs to neither sentence. It records the
/// texts it was asked to split.
class FakeTextAnalyzer implements TextAnalyzer {
  /// Creates the analyzer.
  new();

  /// Every text passed to [sentences], in order.
  final List<String> sentenceCalls = [];

  static final RegExp _sentence = RegExp(r'[^.!?\s][^.!?]*[.!?]*');

  @override
  List<SentenceSpan> sentences(String text) {
    sentenceCalls.add(text);
    return [
      for (final m in _sentence.allMatches(text)) SentenceSpan(m.start, m.end),
    ];
  }

  @override
  List<TextToken> tokens(String text) => [
    for (final m in RegExp(r'\w+').allMatches(text))
      TextToken(m.group(0)!, m.start, m.end),
  ];

  @override
  String lemma(String word) => word.toLowerCase();
}
