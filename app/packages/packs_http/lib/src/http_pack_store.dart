import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core/ports.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'pack_exceptions.dart';

/// Name of the file with installed versions, stored next to the packs.
const packsIndexName = 'packs.json';

final Logger _log = Logger('HttpPackStore');

/// [PackStore] that downloads packs from the service over HTTP.
///
/// Layout of [directory]: `<id>.sqlite` per installed pack and `packs.json`
/// (`{"packs": {"<id>": "<version>"}}`). A download goes to
/// `<id>.sqlite.part`, is checked against size and sha256 from the manifest,
/// then renamed over `<id>.sqlite`, so the old file stays usable until the
/// new one is complete. Failures throw a [PackException].
class HttpPackStore implements PackStore {
  /// Creates a store.
  ///
  /// [baseUri] is the service root (e.g. `http://localhost:8080`),
  /// [directory] holds the packs, [client] is injectable for tests,
  /// [timeout] limits waiting for a response and for the next body chunk.
  new({
    required this.baseUri,
    required this.directory,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  /// Service root.
  final Uri baseUri;

  /// Directory with installed packs and [packsIndexName].
  final Directory directory;

  /// Network timeout.
  final Duration timeout;

  final http.Client _client;
  Future<void> _indexLock = Future<void>.value();

  /// Closes the HTTP client.
  void close() => _client.close();

  Uri _resolve(String path) {
    final base = baseUri.path.endsWith('/') ? baseUri.path : '${baseUri.path}/';
    return baseUri.replace(path: base + path.replaceFirst(RegExp('^/+'), ''));
  }

  File _packFile(String id) => File(p.join(directory.path, '$id.sqlite'));

  File get _indexFile => File(p.join(directory.path, packsIndexName));

  @override
  Future<List<PackManifestEntry>> manifest() async => [
    for (final e in await _fetchManifest()) e.entry,
  ];

  Future<List<_Listed>> _fetchManifest() async {
    _log.fine('GET ${_resolve('manifest.json')}');
    final response = await _guard(
      () => _client.get(_resolve('manifest.json')).timeout(timeout),
    );
    _checkStatus(response.statusCode, 'manifest.json');
    try {
      final doc = jsonDecode(utf8.decode(response.bodyBytes));
      final packs = (doc as Map<String, Object?>)['packs']! as List<Object?>;
      return [
        for (final raw in packs) _parseEntry(raw! as Map<String, Object?>),
      ];
    } on Object catch (e, s) {
      _log.warning('Bad manifest.json', e, s);
      throw PackManifestException('bad manifest.json: $e');
    }
  }

  _Listed _parseEntry(Map<String, Object?> m) {
    final id = m['id']! as String;
    final version = m['version']! as String;
    return _Listed(
      PackManifestEntry(
        id: id,
        version: version,
        sizeBytes: m['size']! as int,
        sha256: (m['sha256']! as String).toLowerCase(),
      ),
      (m['path'] as String?) ?? 'packs/$id-$version.sqlite',
    );
  }

  @override
  Future<List<InstalledPack>> installed() async {
    final index = await _readIndex();
    return [
      for (final e in index.entries)
        if (_packFile(e.key).existsSync())
          InstalledPack(id: e.key, version: e.value),
    ];
  }

  @override
  Future<String?> pathOf(String id) async {
    final index = await _readIndex();
    if (!index.containsKey(id)) return null;
    final file = _packFile(id);
    return file.existsSync() ? file.path : null;
  }

  @override
  Future<InstalledPack> download(String id, PackProgress onProgress) async {
    final listed = (await _fetchManifest()).where((e) => e.entry.id == id);
    if (listed.isEmpty) throw PackNotFoundException(id);
    final entry = listed.first.entry;
    _log.info(
      'Downloading $id ${entry.version} (${entry.sizeBytes} bytes) '
      'from ${_resolve(listed.first.path)}',
    );
    await directory.create(recursive: true);
    final part = File(p.join(directory.path, '$id.sqlite.part'));
    try {
      await _fetchTo(part, _resolve(listed.first.path), entry, onProgress);
      await part.rename(_packFile(id).path);
    } finally {
      if (part.existsSync()) part.deleteSync();
    }
    await _updateIndex((index) => index[id] = entry.version);
    onProgress(1);
    _log.info('Installed $id ${entry.version}');
    return InstalledPack(id: id, version: entry.version);
  }

  Future<void> _fetchTo(
    File part,
    Uri uri,
    PackManifestEntry entry,
    PackProgress onProgress,
  ) async {
    final response = await _guard(
      () => _client.send(http.Request('GET', uri)).timeout(timeout),
    );
    _checkStatus(response.statusCode, uri.path);
    final total = entry.sizeBytes > 0 ? entry.sizeBytes : null;
    final sink = part.openWrite();
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    var received = 0;
    try {
      await _guard(() async {
        await for (final chunk in response.stream.timeout(timeout)) {
          sink.add(chunk);
          hasher.add(chunk);
          received += chunk.length;
          if (total != null) onProgress((received / total).clamp(0.0, 1.0));
        }
      });
    } finally {
      hasher.close();
      await sink.close();
    }
    if (received < entry.sizeBytes) {
      throw PackNetworkException(
        'truncated download of ${entry.id}: $received of ${entry.sizeBytes}',
      );
    }
    final actual = digestSink.value.toString();
    if (actual != entry.sha256) {
      _log.warning('Hash mismatch for ${entry.id}');
      throw PackHashMismatchException(
        id: entry.id,
        expected: entry.sha256,
        actual: actual,
      );
    }
  }

  @override
  Future<void> remove(String id) async {
    await _updateIndex((index) => index.remove(id));
    final file = _packFile(id);
    if (file.existsSync()) await file.delete();
  }

  Future<Map<String, String>> _readIndex() async {
    final file = _indexFile;
    if (!file.existsSync()) return {};
    try {
      final doc = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return {
        for (final e in (doc['packs']! as Map<String, Object?>).entries)
          e.key: e.value! as String,
      };
    } on Object {
      // A corrupt index means "nothing installed"; packs are re-downloadable.
      return {};
    }
  }

  /// Serialises read-modify-write of `packs.json`, replacing it atomically.
  Future<void> _updateIndex(void Function(Map<String, String>) change) {
    final run = _indexLock.then((_) async {
      final index = await _readIndex();
      change(index);
      await directory.create(recursive: true);
      final tmp = File('${_indexFile.path}.tmp');
      await tmp.writeAsString(jsonEncode({'packs': index}), flush: true);
      await tmp.rename(_indexFile.path);
    });
    _indexLock = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  void _checkStatus(int status, String what) {
    if (status != 200) {
      _log.warning('HTTP $status for $what');
      throw PackNetworkException('HTTP $status for $what', statusCode: status);
    }
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on http.ClientException catch (e) {
      _log.warning('Network error', e);
      throw PackNetworkException('network error: ${e.message}', cause: e);
    } on SocketException catch (e) {
      _log.warning('Network error', e);
      throw PackNetworkException('network error: ${e.message}', cause: e);
    } on TimeoutException catch (e) {
      _log.warning('Timeout after $timeout', e);
      throw PackNetworkException('timeout', cause: e);
    }
  }
}

class _Listed {
  const new(this.entry, this.path);

  final PackManifestEntry entry;
  final String path;
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
