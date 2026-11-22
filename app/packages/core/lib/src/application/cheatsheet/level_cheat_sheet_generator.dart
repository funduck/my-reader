import '../../domain/books/locator.dart';
import '../../domain/lookup/cefr_level.dart';
import '../../domain/lookup/cheat_sheet.dart';
import '../../ports/cancel_token.dart';
import '../../ports/cheat_sheet_generator.dart';
import '../../ports/level_dictionary.dart';
import '../../ports/text_analyzer.dart';
import 'cheat_sheet_config.dart';

/// Cheat sheet generator driven by CEFR levels (S-3, S-5).
///
/// Steps: tokens of the text, each reduced to a lemma and given a level; keeps
/// lemmas strictly harder than the user's level (an unknown level is not
/// harder, so those lemmas are dropped); drops lemmas in `knownTerms` and
/// proper names; ranks the rest and takes the first [cheatSheetMaxItems].
///
/// A lemma is taken for a proper name when it occurs with a capital letter
/// not at the start of a sentence and never in lower case. Occurrences at the
/// start of a sentence are ignored: there a capital proves nothing.
///
/// Ranking: harder level first, then lower Zipf frequency (no Zipf counts as
/// the rarest), then more occurrences in the text, then earlier first
/// occurrence.
///
/// Each item carries the lemma as `text`, its level and the first sentence of
/// the text with the lemma as `example`; the translation is left empty.
final class LevelCheatSheetGenerator implements CheatSheetGenerator {
  /// Creates a generator over [analyzer] and [levels].
  const new({required this.analyzer, required this.levels});

  /// Splits the text and reduces words to lemmas.
  final TextAnalyzer analyzer;

  /// Gives the level of a lemma.
  final LevelDictionary levels;

  @override
  Future<CheatSheet> generate({
    required String text,
    required Locator from,
    required Locator to,
    required CefrLevel userLevel,
    Set<String> knownTerms = const {},
    CancelToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final sentences = analyzer.sentences(text);
    final stats = <String, _Stats>{};
    var sentence = 0;
    var order = 0;
    for (final token in analyzer.tokens(text)) {
      while (sentence < sentences.length - 1 &&
          sentences[sentence].end <= token.start) {
        sentence++;
      }
      final lemma = analyzer.lemma(token.text);
      final entry = stats.putIfAbsent(lemma, () => _Stats(order++));
      final span = sentence < sentences.length ? sentences[sentence] : null;
      final atStart =
          span == null || _isFirstToken(text, span.start, token.start);
      entry.add(
        token.text,
        atStart: atStart,
        sentence: span == null
            ? null
            : _sentenceText(text.substring(span.start, span.end)),
      );
    }

    cancel?.throwIfCancelled();
    final ranked = <_Ranked>[];
    for (final MapEntry(key: lemma, value: entry) in stats.entries) {
      if (entry.isProperName || knownTerms.contains(lemma)) continue;
      final word = levels.levelOf(lemma);
      if (!word.level.isHarderThan(userLevel)) continue;
      ranked.add(_Ranked(lemma, word, entry));
    }
    ranked.sort(_compare);
    return CheatSheet(
      from: from,
      to: to,
      items: [
        for (final r in ranked.take(cheatSheetMaxItems))
          CheatSheetItem(
            text: r.lemma,
            kind: CheatSheetItemKind.word,
            level: r.word.level,
            example: r.stats.example,
          ),
      ],
    );
  }
}

final RegExp _letters = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Whether only non-letters lie between [from] and [at] in [text]: the token
/// at [at] is the first word of the sentence that starts at [from].
bool _isFirstToken(String text, int from, int at) =>
    !_letters.hasMatch(text.substring(from, at));

final RegExp _spaces = RegExp(r'\s+');

String _sentenceText(String raw) => raw.trim().replaceAll(_spaces, ' ');

bool _isCapitalized(String word) {
  final first = String.fromCharCode(word.runes.first);
  return first != first.toLowerCase();
}

int _compare(_Ranked a, _Ranked b) {
  final level = b.word.level.index - a.word.level.index;
  if (level != 0) return level;
  final zipf = (a.word.zipf ?? 0).compareTo(b.word.zipf ?? 0);
  if (zipf != 0) return zipf;
  final count = b.stats.count - a.stats.count;
  if (count != 0) return count;
  return a.stats.order - b.stats.order;
}

final class _Ranked {
  const new(this.lemma, this.word, this.stats);

  final String lemma;
  final WordLevel word;
  final _Stats stats;
}

/// What the text says about one lemma.
final class _Stats {
  new(this.order);

  /// Position of the first occurrence among all lemmas.
  final int order;

  /// Number of occurrences.
  int count = 0;

  /// First sentence with the lemma.
  String? example;

  bool _midCapital = false;
  bool _lower = false;

  void add(String word, {required bool atStart, required String? sentence}) {
    count++;
    example ??= sentence;
    if (_isCapitalized(word)) {
      if (!atStart) _midCapital = true;
    } else {
      _lower = true;
    }
  }

  bool get isProperName => _midCapital && !_lower;
}
