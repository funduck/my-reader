import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:packs_http/packs_http.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// One pack version served by the fake service.
class _Pack {
  new(this.id, this.version, this.bytes, {String? sha})
    : sha = sha ?? sha256.convert(bytes).toString();

  final String id;
  final String version;
  final Uint8List bytes;
  final String sha;

  String get path => 'packs/$id-$version.sqlite';

  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'schema_version': 1,
    'size': bytes.length,
    'sha256': sha,
    'path': path,
    'license': 'CC BY-SA 4.0',
  };
}

Uint8List _bytes(int n, int seed) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 7 + seed) & 0xff));

/// Fake service; [packs] and the flags can change between calls.
class _Service {
  List<_Pack> packs = [];
  bool dropAfterFirstChunk = false;
  int manifestStatus = 200;

  Future<http.StreamedResponse> handle(http.BaseRequest request) async {
    final path = request.url.path;
    if (path == '/manifest.json') {
      final body = jsonEncode({
        'manifest_version': 1,
        'generated_at': '2026-01-01T00:00:00Z',
        'packs': [for (final x in packs) x.toJson()],
      });
      return http.StreamedResponse(
        Stream.value(utf8.encode(body)),
        manifestStatus,
      );
    }
    for (final x in packs) {
      if (path == '/${x.path}') {
        final half = x.bytes.length ~/ 2;
        if (dropAfterFirstChunk) {
          return http.StreamedResponse(
            Stream<List<int>>.multi((c) {
              c
                ..add(x.bytes.sublist(0, half))
                ..addError(http.ClientException('Connection closed'));
              unawaited(c.close());
            }),
            200,
          );
        }
        return http.StreamedResponse(
          Stream.fromIterable([
            x.bytes.sublist(0, half),
            x.bytes.sublist(half),
          ]),
          200,
        );
      }
    }
    return http.StreamedResponse(const Stream.empty(), 404);
  }
}

void main() {
  late Directory dir;
  late _Service service;
  late HttpPackStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('packs_http_test');
    service = _Service();
    store = HttpPackStore(
      baseUri: Uri.parse('http://svc.test:8080'),
      directory: dir,
      client: MockClient.streaming((request, _) => service.handle(request)),
    );
  });

  tearDown(() {
    store.close();
    dir.deleteSync(recursive: true);
  });

  List<String> partFiles() => dir
      .listSync()
      .map((e) => p.basename(e.path))
      .where((n) => n.endsWith('.part') || n.endsWith('.tmp'))
      .toList();

  test('manifest parses the service format', () async {
    service.packs = [_Pack('en-en', '20260101.1', _bytes(100, 1))];
    final entries = await store.manifest();
    expect(entries, hasLength(1));
    expect(entries.single.id, 'en-en');
    expect(entries.single.version, '20260101.1');
    expect(entries.single.sizeBytes, 100);
    expect(entries.single.sha256, service.packs.single.sha);
  });

  test('successful download: file, progress, packs.json', () async {
    final pack = _Pack('en-en', '20260101.1', _bytes(1000, 1));
    service.packs = [pack];
    final progress = <double>[];

    final result = await store.download('en-en', progress.add);

    expect(result.id, 'en-en');
    expect(result.version, '20260101.1');
    expect(progress, [0.5, 1.0, 1.0]);
    final path = await store.pathOf('en-en');
    expect(path, p.join(dir.path, 'en-en.sqlite'));
    expect(File(path!).readAsBytesSync(), pack.bytes);
    expect(await store.installed(), [result]);
    expect(partFiles(), isEmpty);
    final index = jsonDecode(
      File(p.join(dir.path, 'packs.json')).readAsStringSync(),
    );
    expect(index, {
      'packs': {'en-en': '20260101.1'},
    });
  });

  test('installed state survives a new store instance (offline)', () async {
    service.packs = [_Pack('en-en', '20260101.1', _bytes(64, 1))];
    await store.download('en-en', (_) {});
    final offline = HttpPackStore(
      baseUri: Uri.parse('http://unreachable.test'),
      directory: dir,
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    expect(await offline.installed(), await store.installed());
    expect(await offline.installed(), hasLength(1));
    expect(await offline.pathOf('en-en'), isNotNull);
    expect(await offline.pathOf('en-forms'), isNull);
  });

  group('connection drop', () {
    test(
      'mid-download throws PackNetworkException, nothing installed',
      () async {
        service
          ..packs = [_Pack('en-en', '20260101.1', _bytes(1000, 1))]
          ..dropAfterFirstChunk = true;

        await expectLater(
          store.download('en-en', (_) {}),
          throwsA(isA<PackNetworkException>()),
        );

        expect(await store.installed(), isEmpty);
        expect(await store.pathOf('en-en'), isNull);
        expect(partFiles(), isEmpty);
      },
    );

    test('drop keeps the previously installed version intact', () async {
      final v1 = _Pack('en-en', '20260101.1', _bytes(500, 1));
      service.packs = [v1];
      await store.download('en-en', (_) {});

      service
        ..packs = [_Pack('en-en', '20260102.1', _bytes(800, 2))]
        ..dropAfterFirstChunk = true;
      await expectLater(
        store.download('en-en', (_) {}),
        throwsA(isA<PackNetworkException>()),
      );

      final installed = await store.installed();
      expect(installed.single.version, '20260101.1');
      expect(File((await store.pathOf('en-en'))!).readAsBytesSync(), v1.bytes);
      expect(partFiles(), isEmpty);
    });

    test('server unreachable on manifest', () async {
      final broken = HttpPackStore(
        baseUri: Uri.parse('http://svc.test'),
        directory: dir,
        client: MockClient((_) async => throw http.ClientException('refused')),
      );
      await expectLater(
        broken.manifest(),
        throwsA(isA<PackNetworkException>()),
      );
    });

    test('HTTP error status carries the code', () async {
      service.manifestStatus = 503;
      await expectLater(
        store.manifest(),
        throwsA(
          isA<PackNetworkException>().having(
            (e) => e.statusCode,
            'status',
            503,
          ),
        ),
      );
    });

    test('stream ending early is a network error, not a hash error', () async {
      final pack = _Pack('en-en', '20260101.1', _bytes(1000, 1));
      final truncated = HttpPackStore(
        baseUri: Uri.parse('http://svc.test'),
        directory: dir,
        client: MockClient.streaming((request, _) async {
          if (request.url.path == '/manifest.json') {
            return http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  jsonEncode({
                    'packs': [pack.toJson()],
                  }),
                ),
              ),
              200,
            );
          }
          return http.StreamedResponse(
            Stream.value(pack.bytes.sublist(0, 400)),
            200,
          );
        }),
      );
      await expectLater(
        truncated.download('en-en', (_) {}),
        throwsA(isA<PackNetworkException>()),
      );
      expect(await truncated.installed(), isEmpty);
    });
  });

  group('wrong hash', () {
    test('throws PackHashMismatchException and installs nothing', () async {
      final bytes = _bytes(1000, 1);
      service.packs = [_Pack('en-en', '20260101.1', bytes, sha: 'ab' * 32)];

      await expectLater(
        store.download('en-en', (_) {}),
        throwsA(
          isA<PackHashMismatchException>()
              .having((e) => e.expected, 'expected', 'ab' * 32)
              .having(
                (e) => e.actual,
                'actual',
                sha256.convert(bytes).toString(),
              ),
        ),
      );

      expect(await store.installed(), isEmpty);
      expect(await store.pathOf('en-en'), isNull);
      expect(File(p.join(dir.path, 'en-en.sqlite')).existsSync(), isFalse);
      expect(partFiles(), isEmpty);
    });

    test('corrupted update does not replace the installed version', () async {
      final v1 = _Pack('en-en', '20260101.1', _bytes(500, 1));
      service.packs = [v1];
      await store.download('en-en', (_) {});

      service.packs = [
        _Pack('en-en', '20260102.1', _bytes(800, 2), sha: 'cd' * 32),
      ];
      await expectLater(
        store.download('en-en', (_) {}),
        throwsA(isA<PackHashMismatchException>()),
      );

      expect((await store.installed()).single.version, '20260101.1');
      expect(File((await store.pathOf('en-en'))!).readAsBytesSync(), v1.bytes);
    });
  });

  group('version update', () {
    test('new version replaces file and packs.json', () async {
      service.packs = [
        _Pack('en-en', '20260101.1', _bytes(500, 1)),
        _Pack('en-forms', '20260101.1', _bytes(300, 3)),
      ];
      await store.download('en-en', (_) {});
      await store.download('en-forms', (_) {});

      final v2 = _Pack('en-en', '20260102.1', _bytes(900, 2));
      service.packs = [v2, service.packs[1]];

      final manifest = await store.manifest();
      final installed = await store.installed();
      final outdated = [
        for (final m in manifest)
          if (installed.any((i) => i.id == m.id && i.version != m.version))
            m.id,
      ];
      expect(outdated, ['en-en']);

      final result = await store.download('en-en', (_) {});

      expect(result.version, '20260102.1');
      expect(File((await store.pathOf('en-en'))!).readAsBytesSync(), v2.bytes);
      final byId = {for (final i in await store.installed()) i.id: i.version};
      expect(byId, {'en-en': '20260102.1', 'en-forms': '20260101.1'});
      expect(partFiles(), isEmpty);
    });

    test('unknown pack id throws PackNotFoundException', () async {
      service.packs = [_Pack('en-en', '20260101.1', _bytes(10, 1))];
      await expectLater(
        store.download('nope', (_) {}),
        throwsA(isA<PackNotFoundException>()),
      );
    });
  });

  test('remove deletes file and packs.json entry', () async {
    service.packs = [_Pack('en-en', '20260101.1', _bytes(64, 1))];
    await store.download('en-en', (_) {});
    await store.remove('en-en');
    expect(await store.installed(), isEmpty);
    expect(await store.pathOf('en-en'), isNull);
    expect(File(p.join(dir.path, 'en-en.sqlite')).existsSync(), isFalse);
    await store.remove('en-en'); // no-op
  });

  test('concurrent downloads keep both entries in packs.json', () async {
    service.packs = [
      _Pack('en-en', '20260101.1', _bytes(200, 1)),
      _Pack('en-forms', '20260101.1', _bytes(300, 2)),
    ];
    await Future.wait([
      store.download('en-en', (_) {}),
      store.download('en-forms', (_) {}),
    ]);
    expect((await store.installed()).map((i) => i.id).toSet(), {
      'en-en',
      'en-forms',
    });
  });

  test('malformed manifest throws PackManifestException', () async {
    final bad = HttpPackStore(
      baseUri: Uri.parse('http://svc.test'),
      directory: dir,
      client: MockClient((_) async => http.Response('not json', 200)),
    );
    await expectLater(bad.manifest(), throwsA(isA<PackManifestException>()));
  });

  test('base URI with a path prefix is respected', () async {
    final requested = <String>[];
    final prefixed = HttpPackStore(
      baseUri: Uri.parse('http://svc.test/api'),
      directory: dir,
      client: MockClient((r) async {
        requested.add(r.url.path);
        return http.Response('{"packs": []}', 200);
      }),
    );
    expect(await prefixed.manifest(), isEmpty);
    expect(requested, ['/api/manifest.json']);
  });

  test('request timeout is a PackNetworkException', () async {
    final slow = HttpPackStore(
      baseUri: Uri.parse('http://svc.test'),
      directory: dir,
      timeout: const Duration(milliseconds: 20),
      client: MockClient((_) => Completer<http.Response>().future),
    );
    await expectLater(slow.manifest(), throwsA(isA<PackNetworkException>()));
  });
}
