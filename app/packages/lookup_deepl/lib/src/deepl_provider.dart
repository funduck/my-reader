import 'dart:async';
import 'dart:convert';

import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

final Logger _log = Logger('DeepLProvider');

/// Id of [DeepLProvider] in history and `UserProfile.providerOrder`.
const deepLProviderId = ProviderId('deepl');

/// Host of the Free plan (keys ending in `:fx`).
const deepLFreeHost = 'api-free.deepl.com';

/// Host of the Pro plan.
const deepLProHost = 'api.deepl.com';

/// How often a pending request checks its [CancelToken].
const _cancelPoll = Duration(milliseconds: 20);

/// Translates a phrase en to ru through `POST /v2/translate` of DeepL.
///
/// The sentence of the query, if any, goes as `context`: DeepL uses it but
/// does not translate it. The answer is one [Sense] with the translation.
/// Failures are [ProviderUnavailable] with a code in `message` (`no_key`,
/// `network`, `timeout`, `bad_key` for 403, `quota` for 456,
/// `rate_limit` for 429, `server_error` for 5xx, `http_<code>` otherwise,
/// `bad_response`) or [LookupNotFound] for an empty translation. The key is
/// never logged or put into a message.
class DeepLProvider implements LookupProvider {
  /// Creates a provider.
  ///
  /// `apiKey` is called on every lookup, because the user may change the key
  /// between requests; `null` or blank means no key. [timeout] limits one
  /// request.
  new({
    required this._client,
    required this._apiKey,
    this.timeout = const Duration(seconds: 10),
  });

  /// Limit of one request.
  final Duration timeout;

  final http.Client _client;
  final Future<String?> Function() _apiKey;

  @override
  ProviderId get id => deepLProviderId;

  @override
  ProviderInfo get info => const ProviderInfo(
    name: 'DeepL',
    isOnline: true,
    modes: {LookupMode.enRu},
  );

  @override
  bool supports(LookupMode mode) => info.modes.contains(mode);

  /// Address of the translate endpoint for [key]: Free keys end in `:fx`.
  static Uri endpointFor(String key) => Uri(
    scheme: 'https',
    host: key.endsWith(':fx') ? deepLFreeHost : deepLProHost,
    path: '/v2/translate',
  );

  @override
  Future<LookupResult> lookup(LookupQuery query, {CancelToken? cancel}) async {
    cancel?.throwIfCancelled();
    if (!supports(query.mode)) {
      throw const ProviderUnavailable('unsupported_mode');
    }
    final key = (await _apiKey())?.trim();
    cancel?.throwIfCancelled();
    if (key == null || key.isEmpty) {
      throw const ProviderUnavailable('no_key');
    }
    final response = await _send(query, key, cancel);
    cancel?.throwIfCancelled();
    return _parse(response);
  }

  Future<http.Response> _send(
    LookupQuery query,
    String key,
    CancelToken? cancel,
  ) async {
    final sentence = query.sentence?.trim();
    final body = jsonEncode({
      'text': [query.text],
      'source_lang': 'EN',
      'target_lang': 'RU',
      if (sentence != null && sentence.isNotEmpty) 'context': sentence,
    });
    final uri = endpointFor(key);
    _log.fine('POST ${uri.host}${uri.path}');
    final request = http.Request('POST', uri)
      ..headers['Authorization'] = 'DeepL-Auth-Key $key'
      ..headers['Content-Type'] = 'application/json; charset=utf-8'
      ..bodyBytes = utf8.encode(body);

    final aborted = Completer<http.Response>();
    final poller = cancel == null
        ? null
        : Timer.periodic(_cancelPoll, (_) {
            if (cancel.isCancelled && !aborted.isCompleted) {
              aborted.completeError(const CancelledException());
            }
          });
    try {
      final pending = _client.send(request).then(http.Response.fromStream);
      // The abandoned request may still fail later; do not leave it unhandled.
      unawaited(pending.then<void>((_) {}, onError: (Object _) {}));
      return await Future.any([pending, aborted.future]).timeout(timeout);
    } on TimeoutException {
      _log.warning('DeepL request timed out');
      throw const ProviderUnavailable('timeout');
    } on CancelledException {
      rethrow;
    } on Object catch (e, s) {
      // ClientException, socket and TLS errors: all mean "no network".
      _log.warning('DeepL request failed', e, s);
      throw const ProviderUnavailable('network');
    } finally {
      poller?.cancel();
    }
  }

  LookupResult _parse(http.Response response) {
    final code = response.statusCode;
    if (code != 200) {
      final reason = switch (code) {
        403 => 'bad_key',
        456 => 'quota',
        429 => 'rate_limit',
        >= 500 && < 600 => 'server_error',
        _ => 'http_$code',
      };
      _log.warning('DeepL answered $code ($reason)');
      throw ProviderUnavailable('$reason: HTTP $code');
    }
    final String text;
    try {
      final doc = jsonDecode(utf8.decode(response.bodyBytes));
      final translations =
          (doc as Map<String, Object?>)['translations']! as List<Object?>;
      final first = translations.first! as Map<String, Object?>;
      text = (first['text'] ?? '') as String;
    } on Object catch (e, s) {
      _log.warning('Bad DeepL response', e, s);
      throw const ProviderUnavailable('bad_response');
    }
    if (text.trim().isEmpty) {
      throw const LookupNotFound('empty translation');
    }
    return LookupResult(
      provider: id,
      senses: [Sense(text: text.trim())],
    );
  }
}
