import '../../domain/books/locator.dart';
import '../../domain/lookup/cefr_level.dart';
import '../../domain/lookup/cheat_sheet.dart';
import '../../ports/cancel_token.dart';
import '../../ports/cheat_sheet_generator.dart';
import '../../ports/level_dictionary.dart';
import '../../ports/text_analyzer.dart';
import 'short_quote.dart';

/// Cheat sheet generator driven by CEFR levels (S-3, S-5).
///
/// Steps: tokens of the text, each reduced to a lemma and given a level; keeps
/// every lemma (so the screen can change the user's level and the limit, or
/// the user can look a word up, without analysing the text again); drops
/// lemmas in `knownTerms`; ranks the rest. No cut by level or count, and no
/// cut of unknown levels or proper names either (T-121: a word that was
/// translated is difficult whatever it is): see `selectCheatSheetItems`.
///
/// A lemma is taken for a proper name when it occurs with a capital letter
/// not at the start of a sentence and never in lower case; the item says so
/// in `isProperName`. Occurrences at the start of a sentence are ignored:
/// there a capital proves nothing.
///
/// Ranking: harder level first (an unknown level last), then lower Zipf
/// frequency (no Zipf counts as the rarest), then more occurrences in the
/// text, then earlier first occurrence.
///
/// Each item carries the lemma as `text`, its level and Zipf frequency, and as
/// `example` a `shortQuote` around the first word form in the text; the
/// translation is left empty.
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
      if (knownTerms.contains(lemma)) continue;
      final word = levels.levelOf(lemma);
      ranked.add(_Ranked(lemma, word, entry));
    }
    ranked.sort(_compare);
    return CheatSheet(
      from: from,
      to: to,
      items: [
        for (final r in ranked)
          CheatSheetItem(
            text: r.lemma,
            kind: CheatSheetItemKind.word,
            level: r.word.level,
            zipf: r.word.zipf,
            isProperName: r.stats.isProperName,
            example: r.stats.sentence == null
                ? null
                : shortQuote(r.stats.sentence!, r.stats.form),
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

/// Position of [level] in the ranking: an unknown level is below A1.
int _rank(CefrLevel level) => level.isKnown ? level.index + 1 : 0;

int _compare(_Ranked a, _Ranked b) {
  final level = _rank(b.word.level) - _rank(a.word.level);
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
  String? sentence;

  /// The word form that stands in [sentence].
  String form = '';

  bool _midCapital = false;
  bool _lower = false;

  void add(String word, {required bool atStart, required String? sentence}) {
    count++;
    if (this.sentence == null && sentence != null) {
      this.sentence = sentence;
      form = word;
    }
    if (_isCapitalized(word)) {
      if (!atStart) _midCapital = true;
    } else {
      _lower = true;
    }
  }

  bool get isProperName => _midCapital && !_lower;
}
