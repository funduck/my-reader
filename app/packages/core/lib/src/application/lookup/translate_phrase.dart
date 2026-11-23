import 'package:meta/meta.dart';

import '../../domain/books/locator.dart';
import '../../domain/lookup/ids.dart';
import '../../domain/lookup/lookup_mode.dart';
import '../../domain/lookup/lookup_query.dart';
import '../../domain/lookup/phrase_lookup.dart';
import '../../ports/cancel_token.dart';
import '../../ports/clock.dart';
import '../../ports/id_generator.dart';
import '../../ports/lookup_provider.dart';
import '../../ports/phrase_journal.dart';
import '../../ports/text_analyzer.dart';

/// Why a phrase could not be translated.
enum PhraseFailureKind {
  /// No API key is stored (`no_key`).
  noKey,

  /// The request did not reach the service (`network`).
  network,

  /// The service did not answer in time (`timeout`).
  timeout,

  /// The service rejected the key (`bad_key`).
  badKey,

  /// The plan's character quota is used up (`quota`).
  quota,

  /// Too many requests (`rate_limit`).
  rateLimit,

  /// The service failed (`server_error`).
  serverError,

  /// Any other failure, including an unreadable answer.
  other,

  /// The provider answered with nothing to show.
  notFound,

  /// The selection is longer than one sentence, or longer than
  /// `TranslatePhrase.maxLength` characters. The provider was not asked.
  tooLong,
}

/// What `TranslatePhrase.call` returns.
sealed class PhraseOutcome {
  const new();
}

/// The phrase was translated. Not in the journal until
/// `TranslatePhrase.record`.
@immutable
final class PhraseTranslated extends PhraseOutcome {
  /// Creates the outcome. [at] should be in UTC.
  const new({
    required this.id,
    required this.text,
    required this.translation,
    required this.provider,
    required this.at,
    this.sentence,
    this.locator,
  });

  /// Id the journal entry gets; the same on every `record` of this outcome.
  final PhraseLookupId id;

  /// The trimmed phrase.
  final String text;

  /// The translation.
  final String translation;

  /// Provider that translated.
  final ProviderId provider;

  /// When the translation arrived.
  final DateTime at;

  /// Context sentence, if known.
  final String? sentence;

  /// Place in the book; without it nothing is recorded.
  final Locator? locator;

  /// The journal entry, `null` without a [locator].
  PhraseLookup? get entry {
    final place = locator;
    if (place == null) return null;
    return PhraseLookup(
      id: id,
      text: text,
      translation: translation,
      provider: provider,
      at: at,
      locator: place,
      sentence: sentence,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PhraseTranslated &&
      other.id == id &&
      other.text == text &&
      other.translation == translation &&
      other.provider == provider &&
      other.at == at &&
      other.sentence == sentence &&
      other.locator == locator;

  @override
  int get hashCode =>
      Object.hash(id, text, translation, provider, at, sentence, locator);
}

/// The phrase could not be translated. Nothing is recorded.
@immutable
final class PhraseFailed extends PhraseOutcome {
  /// Creates the outcome.
  const new({required this.kind, this.message});

  /// What went wrong.
  final PhraseFailureKind kind;

  /// Message of the provider, for logs; never for the user.
  final String? message;

  @override
  bool operator ==(Object other) =>
      other is PhraseFailed && other.kind == kind && other.message == message;

  @override
  int get hashCode => Object.hash(kind, message);
}

/// The scenario "user selected a phrase" (B-009).
///
/// Asks one phrase provider (DeepL) directly, not through `ProviderChain`: the
/// chain's 5 s limit is shorter than the provider's own timeout, which is what
/// this scenario relies on. A selection of more than one sentence (or over
/// [maxLength] characters) is `PhraseFailureKind.tooLong` before any request:
/// DeepL bills by characters. Two steps like `LookupSelection` (T-086): [call]
/// translates and writes nothing; [record] appends the result to the
/// [PhraseJournal] once the caller decides it was seen. Terms and the lookup
/// journal are not touched. Failures are values ([PhraseFailed]); only
/// `CancelledException` is thrown.
class TranslatePhrase {
  /// Creates the scenario over the phrase provider.
  new({
    required this._provider,
    required this._journal,
    required this._clock,
    required this._ids,
    required this._analyzer,
  });

  /// Longest phrase asked from the provider, in characters; the fallback for
  /// text without sentence marks.
  static const int maxLength = 500;

  final LookupProvider _provider;
  final PhraseJournal _journal;
  final Clock _clock;
  final IdGenerator _ids;
  final TextAnalyzer _analyzer;

  /// Translates [text] (trimmed) from English to Russian.
  ///
  /// [sentence] is sent as context and stored; [locator] says where in the
  /// book the phrase is.
  Future<PhraseOutcome> call({
    required String text,
    String? sentence,
    Locator? locator,
    CancelToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final phrase = text.trim();
    if (phrase.length > maxLength || _analyzer.sentences(phrase).length > 1) {
      return const PhraseFailed(kind: PhraseFailureKind.tooLong);
    }
    final query = LookupQuery(
      text: phrase,
      mode: LookupMode.enRu,
      sentence: sentence,
      locator: locator,
    );
    try {
      final result = await _provider.lookup(query, cancel: cancel);
      cancel?.throwIfCancelled();
      final translation = result.senses.isEmpty
          ? ''
          : result.senses.first.text.trim();
      if (translation.isEmpty) {
        return const PhraseFailed(kind: PhraseFailureKind.notFound);
      }
      return PhraseTranslated(
        id: PhraseLookupId(_ids.newId()),
        text: phrase,
        translation: translation,
        provider: result.provider,
        at: _clock.now(),
        sentence: sentence,
        locator: locator,
      );
    } on LookupNotFound catch (e) {
      return PhraseFailed(kind: PhraseFailureKind.notFound, message: e.message);
    } on ProviderUnavailable catch (e) {
      return PhraseFailed(kind: _kindOf(e.message), message: e.message);
    }
  }

  /// Writes [outcome] to the journal.
  ///
  /// Returns `false` when there was nothing to write: the outcome has no
  /// locator. Calling it again for the same outcome changes nothing, because
  /// the entry keeps its id.
  Future<bool> record(PhraseTranslated outcome) async {
    final entry = outcome.entry;
    if (entry == null) return false;
    await _journal.record(entry);
    return true;
  }
}

/// Reads the code a provider puts at the start of `ProviderUnavailable`.
PhraseFailureKind _kindOf(String? message) {
  final code = RegExp('^[a-z0-9_]+').stringMatch(message ?? '');
  return switch (code) {
    'no_key' => PhraseFailureKind.noKey,
    'network' => PhraseFailureKind.network,
    'timeout' => PhraseFailureKind.timeout,
    'bad_key' => PhraseFailureKind.badKey,
    'quota' => PhraseFailureKind.quota,
    'rate_limit' => PhraseFailureKind.rateLimit,
    'server_error' => PhraseFailureKind.serverError,
    _ => PhraseFailureKind.other,
  };
}
