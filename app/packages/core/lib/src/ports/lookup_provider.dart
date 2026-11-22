import '../domain/lookup/ids.dart';
import '../domain/lookup/lookup_mode.dart';
import '../domain/lookup/lookup_query.dart';
import '../domain/lookup/lookup_result.dart';
import '../domain/lookup/provider_info.dart';
import 'cancel_token.dart';

/// Base of the failures [LookupProvider.lookup] reports.
///
/// Providers signal failure by throwing a subtype; they never return an empty
/// or partial result for it. The provider chain (P-4) catches both subtypes and
/// moves on to the next provider.
sealed class LookupFailure implements Exception {
  /// Creates a failure with an optional diagnostic [message].
  const new([this.message]);

  /// Diagnostic text, not shown to the user.
  final String? message;
}

/// The provider cannot answer now: offline, dictionary pack not installed,
/// bad API key, timeout. The chain falls back to the next provider.
final class ProviderUnavailable extends LookupFailure {
  /// Creates the failure.
  const new([super.message]);
}

/// The provider works but has no entry for the query. The chain falls back to
/// the next provider; if all fail this way the UI shows "not found".
final class LookupNotFound extends LookupFailure {
  /// Creates the failure.
  const new([super.message]);
}

/// A translation or definition source (P-1).
///
/// A cancelled call throws [CancelledException] from `cancel_token.dart`.
abstract interface class LookupProvider {
  /// Stable id, stored in history.
  ProviderId get id;

  /// Name, online/offline flag and supported modes.
  ProviderInfo get info;

  /// Returns whether the provider can serve [mode].
  bool supports(LookupMode mode);

  /// Looks up [query]; throws a [LookupFailure] subtype on failure.
  Future<LookupResult> lookup(LookupQuery query, {CancelToken? cancel});
}
