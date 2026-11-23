import 'dart:async';
import 'dart:convert';

import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:lookup_deepl/lookup_deepl.dart';
import 'package:test/test.dart';

const _freeKey = 'secret-free-key:fx';
const _proKey = 'secret-pro-key';

http.Response _ok(String text) => http.Response(
  jsonEncode({
    'translations': [
      {'detected_source_language': 'EN', 'text': text},
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const _phrase = LookupQuery(text: 'give up', mode: LookupMode.enRu);

DeepLProvider _provider(
  MockClient client, {
  String? key = _freeKey,
  Duration timeout = const Duration(seconds: 10),
}) => DeepLProvider(client: client, apiKey: () async => key, timeout: timeout);

void main() {
  lookupProviderContract(
    () => _provider(
      MockClient((request) async {
        final text =
            ((jsonDecode(request.body) as Map<String, Object?>)['text']!
                    as List<Object?>)
                .single!
                .toString();
        return text == 'give up' ? _ok('сдаваться') : _ok('');
      }),
    ),
    known: _phrase,
    unknown: const LookupQuery(text: 'zzzz qqqq', mode: LookupMode.enRu),
    createUnavailable: () => _provider(
      MockClient((_) async => fail('no request without a key')),
      key: null,
    ),
  );

  group('DeepLProvider', () {
    test('info', () {
      final p = _provider(MockClient((_) async => _ok('x')));
      expect(p.id, const ProviderId('deepl'));
      expect(p.info.name, 'DeepL');
      expect(p.info.isOnline, isTrue);
      expect(p.info.modes, {LookupMode.enRu});
      expect(p.supports(LookupMode.enEn), isFalse);
    });

    test(
      'a Free key goes to api-free.deepl.com with the auth header',
      () async {
        late http.Request seen;
        final p = _provider(
          MockClient((r) async {
            seen = r;
            return _ok('сдаваться');
          }),
        );
        await p.lookup(_phrase);
        expect(seen.method, 'POST');
        expect(seen.url, Uri.parse('https://api-free.deepl.com/v2/translate'));
        expect(seen.headers['Authorization'], 'DeepL-Auth-Key $_freeKey');
        expect(seen.headers['Content-Type'], startsWith('application/json'));
      },
    );

    test('a Pro key goes to api.deepl.com', () async {
      late Uri seen;
      final p = _provider(
        MockClient((r) async {
          seen = r.url;
          return _ok('сдаваться');
        }),
        key: _proKey,
      );
      await p.lookup(_phrase);
      expect(seen, Uri.parse('https://api.deepl.com/v2/translate'));
    });

    test(
      'the body has text and languages, no context without a sentence',
      () async {
        late Map<String, Object?> body;
        final p = _provider(
          MockClient((r) async {
            body = jsonDecode(r.body) as Map<String, Object?>;
            return _ok('сдаваться');
          }),
        );
        await p.lookup(_phrase);
        expect(body, {
          'text': ['give up'],
          'source_lang': 'EN',
          'target_lang': 'RU',
        });
      },
    );

    test('the sentence goes as context', () async {
      late Map<String, Object?> body;
      final p = _provider(
        MockClient((r) async {
          body = jsonDecode(r.body) as Map<String, Object?>;
          return _ok('сдаваться');
        }),
      );
      await p.lookup(
        const LookupQuery(
          text: 'give up',
          mode: LookupMode.enRu,
          sentence: 'He did not give up.',
        ),
      );
      expect(body['context'], 'He did not give up.');
      expect(body['text'], ['give up']);
    });

    test('a blank sentence is not sent', () async {
      late Map<String, Object?> body;
      final p = _provider(
        MockClient((r) async {
          body = jsonDecode(r.body) as Map<String, Object?>;
          return _ok('сдаваться');
        }),
      );
      await p.lookup(
        const LookupQuery(text: 'a', mode: LookupMode.enRu, sentence: '  '),
      );
      expect(body.containsKey('context'), isFalse);
    });

    test(
      'the result is one sense without transcription or part of speech',
      () async {
        final p = _provider(MockClient((_) async => _ok(' сдаваться ')));
        final result = await p.lookup(_phrase);
        expect(
          result,
          const LookupResult(
            provider: ProviderId('deepl'),
            senses: [Sense(text: 'сдаваться')],
          ),
        );
      },
    );

    test('non-ASCII answers are decoded as UTF-8', () async {
      final p = _provider(
        MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'translations': [
                  {'text': 'сдаваться'},
                ],
              }),
            ),
            200,
          ),
        ),
      );
      expect((await p.lookup(_phrase)).senses.single.text, 'сдаваться');
    });

    test('the key is read on every request', () async {
      final keys = <String?>['aaa:fx', 'bbb'];
      final hosts = <String>[];
      final p = DeepLProvider(
        client: MockClient((r) async {
          hosts.add(r.url.host);
          return _ok('x');
        }),
        apiKey: () async => keys.removeAt(0),
      );
      await p.lookup(_phrase);
      await p.lookup(_phrase);
      expect(hosts, ['api-free.deepl.com', 'api.deepl.com']);
    });

    test('mode other than enRu is unavailable without a request', () async {
      final p = _provider(MockClient((_) async => fail('no request')));
      await expectLater(
        p.lookup(const LookupQuery(text: 'a', mode: LookupMode.enEn)),
        throwsA(isA<ProviderUnavailable>()),
      );
    });

    for (final key in <String?>[null, '', '  ']) {
      test('no key ($key) is ProviderUnavailable, no request', () async {
        var requests = 0;
        final p = _provider(
          MockClient((_) async {
            requests++;
            return _ok('x');
          }),
          key: key,
        );
        await expectLater(
          p.lookup(_phrase),
          throwsA(
            isA<ProviderUnavailable>().having(
              (e) => e.message,
              'message',
              contains('no_key'),
            ),
          ),
        );
        expect(requests, 0);
      });
    }

    const statuses = {
      403: 'bad_key',
      456: 'quota',
      429: 'rate_limit',
      500: 'server_error',
      503: 'server_error',
      400: 'http_400',
    };
    statuses.forEach((status, code) {
      test('HTTP $status is ProviderUnavailable ($code)', () async {
        final p = _provider(
          MockClient((_) async => http.Response('{"message":"x"}', status)),
        );
        await expectLater(
          p.lookup(_phrase),
          throwsA(
            isA<ProviderUnavailable>().having(
              (e) => e.message,
              'message',
              contains(code),
            ),
          ),
        );
      });
    });

    test('a network error is ProviderUnavailable', () async {
      final p = _provider(
        MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(
        p.lookup(_phrase),
        throwsA(
          isA<ProviderUnavailable>().having(
            (e) => e.message,
            'message',
            'network',
          ),
        ),
      );
    });

    test('a timeout is ProviderUnavailable', () async {
      final never = Completer<http.Response>();
      final p = _provider(
        MockClient((_) => never.future),
        timeout: const Duration(milliseconds: 50),
      );
      await expectLater(
        p.lookup(_phrase),
        throwsA(
          isA<ProviderUnavailable>().having(
            (e) => e.message,
            'message',
            'timeout',
          ),
        ),
      );
    });

    test('the default timeout is 10 seconds', () {
      final p = DeepLProvider(
        client: MockClient((_) async => _ok('x')),
        apiKey: () async => null,
      );
      expect(p.timeout, const Duration(seconds: 10));
    });

    test('a garbled body is ProviderUnavailable', () async {
      final p = _provider(
        MockClient((_) async => http.Response('<html>', 200)),
      );
      await expectLater(p.lookup(_phrase), throwsA(isA<ProviderUnavailable>()));
    });

    test('an empty translations list is ProviderUnavailable', () async {
      final p = _provider(
        MockClient((_) async => http.Response('{"translations":[]}', 200)),
      );
      await expectLater(p.lookup(_phrase), throwsA(isA<ProviderUnavailable>()));
    });

    test('an empty translation is LookupNotFound', () async {
      final p = _provider(MockClient((_) async => _ok('  ')));
      await expectLater(p.lookup(_phrase), throwsA(isA<LookupNotFound>()));
    });

    test('cancel while the request is in flight', () async {
      final never = Completer<http.Response>();
      final p = _provider(MockClient((_) => never.future));
      final cancel = CancelToken();
      final future = p.lookup(_phrase, cancel: cancel);
      final expectation = expectLater(
        future,
        throwsA(isA<CancelledException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      cancel.cancel();
      await expectation;
    });

    test('a token cancelled beforehand sends nothing', () async {
      final p = _provider(MockClient((_) async => fail('no request')));
      final cancel = CancelToken()..cancel();
      await expectLater(
        p.lookup(_phrase, cancel: cancel),
        throwsA(isA<CancelledException>()),
      );
    });

    test('the key never reaches the log or a failure message', () async {
      final records = <LogRecord>[];
      final previous = Logger.root.level;
      Logger.root.level = Level.ALL;
      final sub = Logger.root.onRecord.listen(records.add);
      addTearDown(() async {
        await sub.cancel();
        Logger.root.level = previous;
      });
      final messages = <String>[];
      for (final status in [200, 403, 456, 429, 500]) {
        final p = _provider(
          MockClient(
            (_) async => status == 200
                ? _ok('сдаваться')
                : http.Response('error', status),
          ),
        );
        try {
          await p.lookup(_phrase);
        } on LookupFailure catch (e) {
          messages.add('${e.message}');
        }
      }
      final offline = _provider(
        MockClient((_) async => throw http.ClientException('offline')),
      );
      try {
        await offline.lookup(_phrase);
      } on LookupFailure catch (e) {
        messages.add('${e.message}');
      }
      expect(records, isNotEmpty);
      for (final text in [
        for (final r in records) '${r.message} ${r.error} ${r.stackTrace}',
        ...messages,
      ]) {
        expect(text, isNot(contains('secret-free-key')));
      }
    });
  });
}
