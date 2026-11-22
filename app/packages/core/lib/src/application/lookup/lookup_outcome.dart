import '../../domain/lookup/cefr_level.dart';
import '../../domain/lookup/lookup_event.dart';
import '../../domain/lookup/lookup_result.dart';
import '../../domain/lookup/term.dart';
import '../../ports/level_dictionary.dart';
import 'provider_chain.dart';

/// What `LookupSelection` returns; the lookup sheet switches on it.
sealed class LookupOutcome {
  const new({required this.event, required this.term, required this.wordLevel});

  /// The journal entry written for this lookup.
  final LookupEvent event;

  /// The term after the upsert.
  final Term term;

  /// What the `LevelDictionary` said about the looked-up lemma (or phrase)
  /// at lookup time; `WordLevel(CefrLevel.unknown)` if it has no data.
  ///
  /// Unlike `term.level`, it does not fall back to a level remembered from an
  /// earlier lookup, and it tells whether the level is [WordLevel.estimated].
  final WordLevel wordLevel;

  /// CEFR level of the word, [CefrLevel.unknown] if not known.
  CefrLevel get level => wordLevel.level;
}

/// A provider answered.
final class LookupAnswered extends LookupOutcome {
  /// Creates the outcome.
  const new({
    required super.event,
    required super.term,
    required super.wordLevel,
    required this.skipped,
  });

  /// The answer, same as `event.result`.
  LookupResult get result => event.result;

  /// Providers that failed before the answering one.
  final List<ProviderAttempt> skipped;
}

/// No provider answered. The event is still written, with a result that has
/// no senses.
final class LookupUnanswered extends LookupOutcome {
  /// Creates the outcome.
  const new({
    required super.event,
    required super.term,
    required super.wordLevel,
    required this.failure,
  });

  /// What each provider did.
  final ChainFailure failure;

  /// Whether the UI shows "not found" (otherwise "unavailable").
  bool get isNotFound => failure.isNotFound;
}
