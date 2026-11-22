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
