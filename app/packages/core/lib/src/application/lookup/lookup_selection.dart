import '../../domain/books/locator.dart';
import '../../domain/lookup/ids.dart';
import '../../domain/lookup/lookup_event.dart';
import '../../domain/lookup/lookup_mode.dart';
import '../../domain/lookup/lookup_query.dart';
import '../../domain/lookup/lookup_result.dart';
import '../../domain/lookup/term.dart';
import '../../ports/cancel_token.dart';
import '../../ports/clock.dart';
import '../../ports/id_generator.dart';
import '../../ports/level_dictionary.dart';
import '../../ports/repositories.dart';
import '../../ports/text_analyzer.dart';
import 'lookup_outcome.dart';
import 'provider_chain.dart';

/// Provider id written into the event when no provider was tried at all.
const noProvider = ProviderId('none');

/// Language of terms made by [LookupSelection]; only English for now.
const lookupLanguage = 'en';

/// The scenario "user selected a word" (T-1, P-4, H-1, H-2, H-4).
///
/// Steps: build the query, run the [ProviderChain], append a `LookupEvent`,
/// upsert the `Term`. The event is written for every finished lookup, also
/// when all providers failed (then its result has no senses and names the
/// last provider tried, or [noProvider]). The term is upserted in every case
/// too, so it stays rebuildable from the journal: `lookupCount` counts events
/// and `eventIds` lists them.
///
/// The outcome also carries the `WordLevel` of the same key (lemma of a
/// single word, lower-cased text of a phrase), so the lemma is chosen here,
/// not by the caller.
///
/// A lookup cancelled through the token writes nothing and throws
/// `CancelledException`. The query text is the trimmed selection; the term is
/// keyed by the lemma of a single word, or the lower-cased text of a phrase.
class LookupSelection {
  /// Creates the scenario.
  new({
    required this._chain,
    required this._analyzer,
    required this._levels,
    required this._journal,
    required this._terms,
    required this._profiles,
    required this._clock,
    required this._ids,
  });

  final ProviderChain _chain;
  final TextAnalyzer _analyzer;
  final LevelDictionary _levels;
  final LookupJournal _journal;
  final TermRepository _terms;
  final ProfileRepository _profiles;
  final Clock _clock;
  final IdGenerator _ids;

  /// Looks up [text].
  ///
  /// [mode] defaults to the profile mode. [provider] asks one provider with no
  /// fallback (switching provider in the sheet); each call makes its own
  /// event. [sentence] and [locator] are stored for history (H-2).
  Future<LookupOutcome> call({
    required String text,
    LookupMode? mode,
    String? sentence,
    Locator? locator,
    ProviderId? provider,
    CancelToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final query = LookupQuery(
      text: text.trim(),
      mode: mode ?? (await _profiles.get()).mode,
      sentence: sentence,
      locator: locator,
    );
    final chain = await _chain.lookup(query, only: provider, cancel: cancel);
    cancel?.throwIfCancelled();

    final result = switch (chain) {
      ChainSuccess(:final result) => result,
      ChainFailure(:final attempts) => LookupResult(
        provider: attempts.isEmpty ? noProvider : attempts.last.provider,
        senses: const [],
      ),
    };
    final (event, term, wordLevel) = await _record(query, result);
    return switch (chain) {
      ChainSuccess(:final failedBefore) => LookupAnswered(
        event: event,
        term: term,
        wordLevel: wordLevel,
        skipped: failedBefore,
      ),
      ChainFailure() => LookupUnanswered(
        event: event,
        term: term,
        wordLevel: wordLevel,
        failure: chain,
      ),
    };
  }

  Future<(LookupEvent, Term, WordLevel)> _record(
    LookupQuery query,
    LookupResult result,
  ) async {
    final event = LookupEvent(
      id: LookupEventId(_ids.newId()),
      query: query,
      result: result,
      at: _clock.now(),
    );
    await _journal.record(event);

    final normalized = _normalize(query.text);
    final wordLevel = _levels.levelOf(normalized);
    final level = wordLevel.level;
    final existing = await _terms.find(normalized, lookupLanguage);
    final Term term;
    if (existing == null) {
      term = Term(
        id: TermId(_ids.newId()),
        normalized: normalized,
        language: lookupLanguage,
        lookupCount: 1,
        eventIds: [event.id],
        level: level,
      );
    } else {
      term = existing.copyWith(
        lookupCount: existing.lookupCount + 1,
        eventIds: [...existing.eventIds, event.id],
        level: level.isKnown ? level : existing.level,
      );
    }
    await _terms.save(term);
    return (event, term, wordLevel);
  }

  /// Lemma for a single word; lower-cased, space-collapsed text for a phrase.
  String _normalize(String text) {
    final tokens = _analyzer.tokens(text);
    if (tokens.length == 1) return _analyzer.lemma(tokens.single.text);
    return text.toLowerCase().split(RegExp(r'\s+')).join(' ');
  }
}
