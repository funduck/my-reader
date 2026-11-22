import 'dart:async';

import 'package:meta/meta.dart';

import '../../domain/lookup/ids.dart';
import '../../domain/lookup/lookup_query.dart';
import '../../domain/lookup/lookup_result.dart';
import '../../ports/cancel_token.dart';
import '../../ports/lookup_provider.dart';
import '../../ports/repositories.dart';

/// Why one provider did not give an answer.
enum AttemptFailure {
  /// The provider threw [ProviderUnavailable].
  unavailable,

  /// The provider threw [LookupNotFound].
  notFound,

  /// The provider returned a result without senses.
  empty,

  /// The provider did not answer within the chain timeout.
  timedOut,

  /// Explicit provider only: it does not support the mode of the query.
  unsupported,

  /// Explicit provider only: no provider with this id is registered.
  unregistered,
}

/// One failed step of a chain run.
@immutable
final class ProviderAttempt {
  /// Creates an attempt record.
  const new(this.provider, this.failure);

  /// The provider that was tried.
  final ProviderId provider;

  /// Why it gave no answer.
  final AttemptFailure failure;

  @override
  bool operator ==(Object other) =>
      other is ProviderAttempt &&
      other.provider == provider &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(provider, failure);

  @override
  String toString() => 'ProviderAttempt(${provider.value}, ${failure.name})';
}

/// Outcome of [ProviderChain.lookup].
sealed class ChainResult {
  const new();
}

/// A provider answered with at least one sense.
final class ChainSuccess extends ChainResult {
  /// Creates the result.
  const new(this.result, this.failedBefore);

  /// The answer; [LookupResult.provider] tells who gave it.
  final LookupResult result;

  /// Providers that were tried and failed before the answering one.
  final List<ProviderAttempt> failedBefore;
}

/// No provider answered.
final class ChainFailure extends ChainResult {
  /// Creates the result.
  const new(this.attempts);

  /// Every step, in the order tried; empty if no provider supports the mode.
  final List<ProviderAttempt> attempts;

  /// Whether providers were tried and every one of them found nothing.
  ///
  /// The UI shows "not found" for it and "unavailable" otherwise.
  bool get isNotFound =>
      attempts.isNotEmpty &&
      attempts.every(
        (a) =>
            a.failure == AttemptFailure.notFound ||
            a.failure == AttemptFailure.empty,
      );
}

/// Tries providers one after another until one answers (P-4).
///
/// Order: the user's `UserProfile.providerOrder`; providers it lists come
/// first, in that order, then the rest in registration order. An empty order
/// means registration order. Providers that do not support the mode of the
/// query are skipped. A provider that throws a [LookupFailure], returns no
/// senses or exceeds [timeout] is skipped too. Any other exception is a bug
/// and propagates.
class ProviderChain {
  /// Creates a chain over [providers] (registration order).
  ///
  /// The profile is read on every call, so order changes apply at once.
  new({
    required List<LookupProvider> providers,
    required this._profiles,
    this.timeout = defaultTimeout,
  }) : _providers = List.unmodifiable(providers);

  /// Time one provider gets before the chain moves on.
  static const defaultTimeout = Duration(seconds: 5);

  /// Time one provider gets before the chain moves on.
  final Duration timeout;

  final List<LookupProvider> _providers;
  final ProfileRepository _profiles;

  /// Looks up [query], in the order from the profile.
  ///
  /// With [only] just that provider is called, with no fallback (the user
  /// picked it in the sheet). Throws `CancelledException` if [cancel] is
  /// cancelled before the run or after a provider returns; the token is also
  /// passed to the providers, which stop cooperatively.
  Future<ChainResult> lookup(
    LookupQuery query, {
    ProviderId? only,
    CancelToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final List<LookupProvider> candidates;
    if (only != null) {
      final provider = _find(only);
      if (provider == null) {
        return ChainFailure([
          ProviderAttempt(only, AttemptFailure.unregistered),
        ]);
      }
      if (!provider.supports(query.mode)) {
        return ChainFailure([
          ProviderAttempt(only, AttemptFailure.unsupported),
        ]);
      }
      candidates = [provider];
    } else {
      final profile = await _profiles.get();
      cancel?.throwIfCancelled();
      candidates = _ordered(profile.providerOrder, query);
    }
    final attempts = <ProviderAttempt>[];
    for (final provider in candidates) {
      final result = await _tryOne(provider, query, cancel, attempts);
      if (result != null) return ChainSuccess(result, List.of(attempts));
    }
    return ChainFailure(attempts);
  }

  LookupProvider? _find(ProviderId id) {
    for (final p in _providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<LookupProvider> _ordered(List<ProviderId> order, LookupQuery query) {
    final result = <LookupProvider>[];
    for (final id in order) {
      final p = _find(id);
      if (p != null && !result.contains(p)) result.add(p);
    }
    for (final p in _providers) {
      if (!result.contains(p)) result.add(p);
    }
    return [
      for (final p in result)
        if (p.supports(query.mode)) p,
    ];
  }

  Future<LookupResult?> _tryOne(
    LookupProvider provider,
    LookupQuery query,
    CancelToken? cancel,
    List<ProviderAttempt> attempts,
  ) async {
    AttemptFailure failure;
    try {
      final result = await provider
          .lookup(query, cancel: cancel)
          .timeout(timeout);
      cancel?.throwIfCancelled();
      if (result.senses.isNotEmpty) return result;
      failure = AttemptFailure.empty;
    } on TimeoutException {
      failure = AttemptFailure.timedOut;
    } on ProviderUnavailable {
      failure = AttemptFailure.unavailable;
    } on LookupNotFound {
      failure = AttemptFailure.notFound;
    }
    attempts.add(ProviderAttempt(provider.id, failure));
    return null;
  }
}
