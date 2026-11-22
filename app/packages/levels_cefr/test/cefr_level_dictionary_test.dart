import 'dart:io';

import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:levels_cefr/levels_cefr.dart';
import 'package:test/test.dart';

const _packPath = '../../../service/fixtures/packs/en-levels-20260101.1.sqlite';

final class _Store implements PackStore {
  new(this.path);

  final String? path;

  @override
  Future<String?> pathOf(String id) async => id == 'en-levels' ? path : null;

  @override
  Future<List<PackManifestEntry>> manifest() => throw UnimplementedError();

  @override
  Future<List<InstalledPack>> installed() => throw UnimplementedError();

  @override
  Future<InstalledPack> download(String id, PackProgress onProgress) =>
      throw UnimplementedError();

  @override
  Future<void> remove(String id) => throw UnimplementedError();
}

void main() {
  late CefrLevelDictionary dict;

  setUp(() {
    expect(File(_packPath).existsSync(), isTrue, reason: 'mini pack missing');
    dict = CefrLevelDictionary.fromPath(_packPath);
  });

  tearDown(() => dict.close());

  test('known word without pos', () {
    expect(dict.levelOf('cat').level, CefrLevel.a1);
    expect(dict.levelOf('ephemeral').level, CefrLevel.c2);
  });

  test('known word with pos', () {
    expect(dict.levelOf('book', pos: 'verb').level, CefrLevel.b1);
    expect(dict.levelOf('book', pos: 'noun').level, CefrLevel.a1);
    expect(dict.levelOf('light', pos: 'adj').level, CefrLevel.b1);
  });

  test('without pos the minimum level among variants wins', () {
    expect(dict.levelOf('book').level, CefrLevel.a1);
    expect(dict.levelOf('light').level, CefrLevel.a2);
    expect(dict.levelOf('well').level, CefrLevel.a1);
    expect(dict.levelOf('go').level, CefrLevel.a1);
  });

  test('pos missing for the lemma falls back to all variants', () {
    expect(dict.levelOf('cat', pos: 'verb').level, CefrLevel.a1);
  });

  test('pos any entries match every pos', () {
    expect(dict.levelOf('ubiquitous', pos: 'adj').level, CefrLevel.c1);
  });

  test('unknown word', () {
    expect(dict.levelOf('zzzz'), const WordLevel(CefrLevel.unknown));
    expect(dict.levelOf(''), const WordLevel(CefrLevel.unknown));
  });

  test('unknown level is ignored if a known one exists, else kept', () {
    // paris: only a row with NULL cefr; lantern likewise.
    expect(
      dict.levelOf('lantern'),
      const WordLevel(CefrLevel.unknown, zipf: 3.2),
    );
    expect(dict.levelOf('whisper').level, CefrLevel.unknown);
  });

  test('estimated flag and zipf are returned', () {
    expect(
      dict.levelOf('ubiquitous'),
      const WordLevel(CefrLevel.c1, estimated: true, zipf: 3),
    );
    expect(dict.levelOf('cat'), const WordLevel(CefrLevel.a1, zipf: 4.9));
    expect(dict.levelOf('mother-in-law').zipf, isNull);
    expect(dict.levelOf('mother-in-law').level, CefrLevel.b1);
  });

  test('keys are normalized', () {
    expect(dict.levelOf('  CAT ').level, CefrLevel.a1);
    expect(dict.levelOf('Mother-In-Law').level, CefrLevel.b1);
    expect(dict.levelOf('book', pos: ' Verb ').level, CefrLevel.b1);
    expect(CefrLevelDictionary.normalizeKey('Don’t  Stop'), "don't stop");
  });

  test('open through PackStore', () async {
    final opened = await CefrLevelDictionary.open(_Store(_packPath));
    addTearDown(opened.close);
    expect(opened.levelOf('dog').level, CefrLevel.a1);
  });

  test('missing pack answers unknown', () async {
    final empty = await CefrLevelDictionary.open(_Store(null));
    expect(empty.levelOf('dog'), const WordLevel(CefrLevel.unknown));
    empty.close();
  });
}
