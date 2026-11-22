import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';

/// A [LookupProvider] with scripted answers, delay and failure.
///
/// Answers are keyed by the lower-cased, trimmed query text. A text without
/// an answer throws [LookupNotFound]. When [failure] is set every call throws
/// it, whatever the text.
class FakeLookupProvider implements LookupProvider {
  /// Creates a provider.
  ///
  /// [answers] maps lower-case query text to the result returned for it.
  new({
    required this.id,
    this.info = const ProviderInfo(
      name: 'Fake',
      isOnline: false,
      modes: {LookupMode.enEn, LookupMode.enRu},
    ),
    Map<String, LookupResult> answers = const {},
    this.delay = Duration.zero,
    this.failure,
  }) : answers = Map.of(answers);

  @override
  final ProviderId id;

  @override
  final ProviderInfo info;

  /// Scripted results by lower-case query text; tests may edit it.
  final Map<String, LookupResult> answers;

  /// Time each call takes before answering or failing.
  Duration delay;

  /// If not null, every lookup throws this.
  LookupFailure? failure;

  final List<LookupQuery> _calls = [];

  /// Queries received so far, in order, including failed and cancelled ones.
  List<LookupQuery> get calls => List.unmodifiable(_calls);

  @override
  bool supports(LookupMode mode) => info.modes.contains(mode);

  @override
  Future<LookupResult> lookup(LookupQuery query, {CancelToken? cancel}) async {
    _calls.add(query);
    cancel?.throwIfCancelled();
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    cancel?.throwIfCancelled();
    final failure = this.failure;
    if (failure != null) throw failure;
    final result = answers[query.text.trim().toLowerCase()];
    if (result == null) throw LookupNotFound('no entry for ${query.text}');
    return result;
  }
}
