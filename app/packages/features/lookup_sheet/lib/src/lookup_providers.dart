import 'package:core/application.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;

/// The lookup scenario, built from the port providers of `features_common`.
final Provider<LookupSelection> lookupSelectionProvider =
    Provider<LookupSelection>((ref) {
      final profiles = ref.watch(profileRepositoryProvider);
      return LookupSelection(
        chain: ProviderChain(
          providers: ref.watch(lookupProvidersProvider),
          profiles: profiles,
        ),
        analyzer: ref.watch(textAnalyzerProvider),
        levels: ref.watch(levelDictionaryProvider),
        journal: ref.watch(lookupJournalProvider),
        terms: ref.watch(termRepositoryProvider),
        profiles: profiles,
        clock: ref.watch(clockProvider),
        ids: ref.watch(idGeneratorProvider),
      );
    });

/// The provider of phrase translations (DeepL).
///
/// Not part of [lookupProvidersProvider]: phrases never go through the
/// dictionary chain. Throws `PortNotWiredError` until the app wires it.
final Provider<LookupProvider> phraseProviderProvider =
    Provider<LookupProvider>(
      (ref) => throw PortNotWiredError('phraseProviderProvider'),
      name: 'phraseProviderProvider',
    );

/// The phrase scenario, built from the port providers of `features_common`.
final Provider<TranslatePhrase> translatePhraseProvider =
    Provider<TranslatePhrase>(
      (ref) => TranslatePhrase(
        provider: ref.watch(phraseProviderProvider),
        journal: ref.watch(phraseJournalProvider),
        clock: ref.watch(clockProvider),
        ids: ref.watch(idGeneratorProvider),
      ),
    );

/// Outcome of translating the phrase of a query; one run per query while the
/// sheet is open. Disposing the provider cancels the running request. Refresh
/// it to retry.
final FutureProviderFamily<PhraseOutcome, LookupQuery> phraseOutcomeProvider =
    FutureProvider.autoDispose.family<PhraseOutcome, LookupQuery>((ref, query) {
      final cancel = CancelToken();
      ref.onDispose(cancel.cancel);
      return ref.watch(translatePhraseProvider)(
        text: query.text,
        sentence: query.sentence,
        locator: query.locator,
        cancel: cancel,
      );
    }, retry: (_, _) => null);

/// A lookup to run: the `query` and, when the user picked one, the only
/// `provider` to ask (`null` means the chain in the profile order).
typedef LookupRequest = ({LookupQuery query, ProviderId? provider});

/// Outcome of a [LookupRequest]; one run per request while the sheet is open.
/// Disposing the provider cancels the running lookup.
final FutureProviderFamily<LookupOutcome, LookupRequest> lookupOutcomeProvider =
    FutureProvider.autoDispose.family<LookupOutcome, LookupRequest>((
      ref,
      request,
    ) {
      final cancel = CancelToken();
      ref.onDispose(cancel.cancel);
      final query = request.query;
      return ref.watch(lookupSelectionProvider)(
        text: query.text,
        mode: query.mode,
        sentence: query.sentence,
        locator: query.locator,
        provider: request.provider,
        cancel: cancel,
      );
    }, retry: (_, _) => null);

/// Looks the word up in the other mode in the background, only in offline
/// providers (no network use, no cost), one by one in registration order.
///
/// Gives the first [LookupAnswered]; the last "nothing found" when every one
/// of them found nothing; `null` when nothing was asked or the answer is
/// unclear (no offline provider, a provider unavailable). Nothing is written
/// to the history: the sheet records the outcome only if it shows it (T-086).
final FutureProviderFamily<LookupOutcome?, LookupQuery> otherModeProbeProvider =
    FutureProvider.autoDispose.family<LookupOutcome?, LookupQuery>((
      ref,
      query,
    ) async {
      final cancel = CancelToken();
      ref.onDispose(cancel.cancel);
      final selection = ref.watch(lookupSelectionProvider);
      final offline = [
        for (final p in ref.watch(lookupProvidersProvider))
          if (!p.info.isOnline && p.supports(query.mode)) p,
      ];
      LookupOutcome? notFound;
      var unclear = false;
      for (final p in offline) {
        final outcome = await selection(
          text: query.text,
          mode: query.mode,
          sentence: query.sentence,
          locator: query.locator,
          provider: p.id,
          cancel: cancel,
        );
        switch (outcome) {
          case LookupAnswered():
            return outcome;
          case LookupUnanswered(isNotFound: true):
            notFound = outcome;
          case LookupUnanswered():
            unclear = true;
        }
      }
      return unclear ? null : notFound;
    }, retry: (_, _) => null);
