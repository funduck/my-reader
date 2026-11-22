import '../../domain/lookup/cefr_level.dart';
import '../../domain/lookup/lookup_event.dart';
import '../../domain/lookup/lookup_result.dart';
import '../../domain/lookup/term.dart';
import 'provider_chain.dart';

/// What `LookupSelection` returns; the lookup sheet switches on it.
sealed class LookupOutcome {
  const new({required this.event, required this.term});

  /// The journal entry written for this lookup.
  final LookupEvent event;

  /// The term after the upsert.
  final Term term;

  /// CEFR level of the term, [CefrLevel.unknown] if not known.
  CefrLevel get level => term.level;
}

/// A provider answered.
final class LookupAnswered extends LookupOutcome {
  /// Creates the outcome.
  const new({required super.event, required super.term, required this.skipped});

  /// The answer, same as `event.result`.
  LookupResult get result => event.result;

  /// Providers that failed before the answering one.
  final List<ProviderAttempt> skipped;
}

/// No provider answered. The event is still written, with a result that has
/// no senses.
final class LookupUnanswered extends LookupOutcome {
  /// Creates the outcome.
  const new({required super.event, required super.term, required this.failure});

  /// What each provider did.
  final ChainFailure failure;

  /// Whether the UI shows "not found" (otherwise "unavailable").
  bool get isNotFound => failure.isNotFound;
}
