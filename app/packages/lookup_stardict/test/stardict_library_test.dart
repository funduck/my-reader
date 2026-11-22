import 'dart:io';

import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:lookup_stardict/lookup_stardict.dart';
import 'package:test/test.dart';

import 'fixtures/build.dart';

LookupQuery _q(String text, {LookupMode mode = LookupMode.enRu}) =>
    LookupQuery(text: text, mode: mode);

const _entries = [
  FixtureEntry('apple', 'яблоко'),
  FixtureEntry('Bank', 'берег'),
  FixtureEntry('bank', 'банк'),
  FixtureEntry('empty', ''),
];

void main() {
  late Directory tmp;
  late StarDictLibrary library;
  late String source;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('stardict_lib_');
    source = '${tmp.path}/source';
    library = StarDictLibrary(directory: '${tmp.path}/library');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  List<String> files(String base, {bool dz = false}) => [
    '$base.ifo',
    '$base.idx',
    '$base.dict${dz ? '.dz' : ''}',
  ];

  Future<StarDictDictionary> importPlain({
    String name = 'Test dictionary',
    LookupMode mode = LookupMode.enRu,
  }) {
    final base = buildStarDict(_entries, bookName: name).writeTo(source, 'a');
    return library.import(files(base), mode: mode);
  }

  group('contract', () {
    late StarDictDictionary dictionary;
    setUp(() async => dictionary = await importPlain());

    lookupProviderContract(
      () {
        final provider = library.providerFor(dictionary);
        addTearDown(provider.close);
        return provider;
      },
      known: _q('apple'),
      unknown: _q('zzz'),
      createUnavailable: () => StarDictLookupProvider(
        StarDictDictionary(
          id: 'gone',
          name: 'Gone',
          mode: LookupMode.enRu,
          wordCount: 1,
          directory: '${tmp.path}/nowhere',
        ),
      ),
    );
  });

  group('StarDictLibrary', () {
    test('imports a .dict set; the default mode is enRu', () async {
      final dictionary = await importPlain();
      expect(dictionary.id, 'test-dictionary');
      expect(dictionary.name, 'Test dictionary');
      expect(dictionary.mode, LookupMode.enRu);
      expect(dictionary.wordCount, 4);
      expect(Directory(dictionary.directory).existsSync(), isTrue);
      expect(await library.list(), [dictionary]);
    });

    test('imports a .dict.dz set', () async {
      final base = buildStarDict(_entries).writeDzTo(source, 'z');
      final dictionary = await library.import(files(base, dz: true));
      final provider = library.providerFor(dictionary);
      addTearDown(provider.close);
      final result = await provider.lookup(_q('apple'));
      expect(result.senses.single.text, 'яблоко');
    });

    test('keeps the mode chosen at import after a restart', () async {
      await importPlain(mode: LookupMode.enEn);
      final reopened = StarDictLibrary(directory: library.directory);
      final listed = await reopened.list();
      expect(listed.single.mode, LookupMode.enEn);
      expect(
        listed.single.providerId,
        const ProviderId('stardict.test-dictionary'),
      );
      final provider = reopened.providerFor(listed.single);
      addTearDown(provider.close);
      expect(provider.supports(LookupMode.enEn), isTrue);
      expect(provider.supports(LookupMode.enRu), isFalse);
    });

    test('same title twice gets distinct ids', () async {
      final first = await importPlain();
      final second = await importPlain();
      expect(second.id, '${first.id}-2');
      expect((await library.list()).map((d) => d.id), [first.id, second.id]);
    });

    test('get returns the dictionary or null', () async {
      final dictionary = await importPlain();
      expect(await library.get(dictionary.id), dictionary);
      expect(await library.get('missing'), isNull);
      expect(await library.get('../x'), isNull);
    });

    test('remove deletes the files and reports whether it existed', () async {
      final dictionary = await importPlain();
      expect(await library.remove(dictionary.id), isTrue);
      expect(Directory(dictionary.directory).existsSync(), isFalse);
      expect(await library.list(), isEmpty);
      expect(await library.remove(dictionary.id), isFalse);
    });

    test('list of a library that was never written is empty', () async {
      expect(await library.list(), isEmpty);
    });

    test('a file missing from the set is a FormatException', () async {
      final base = buildStarDict(_entries).writeTo(source, 'a');
      await expectLater(
        library.import(['$base.ifo', '$base.idx']),
        throwsFormatException,
      );
    });

    test('a bad .idx leaves nothing behind', () async {
      final base = buildStarDict(_entries).writeTo(source, 'a');
      File('$base.idx').writeAsBytesSync([1, 2, 3]);
      await expectLater(library.import(files(base)), throwsFormatException);
      expect(await library.list(), isEmpty);
      expect(Directory(library.directory).listSync(), isEmpty);
    });

    test('a broken .dict.dz leaves nothing behind', () async {
      final base = buildStarDict(_entries).writeDzTo(source, 'z');
      File('$base.dict.dz').writeAsBytesSync([1, 2, 3, 4]);
      await expectLater(
        library.import(files(base, dz: true)),
        throwsFormatException,
      );
      expect(Directory(library.directory).listSync(), isEmpty);
    });

    test('a missing source file is a FileSystemException', () async {
      final base = buildStarDict(_entries).writeTo(source, 'a');
      File('$base.dict').deleteSync();
      await expectLater(
        library.import(files(base)),
        throwsA(isA<FileSystemException>()),
      );
      expect(Directory(library.directory).listSync(), isEmpty);
    });

    test('a leftover import folder is not listed', () async {
      await importPlain();
      Directory('${library.directory}/.import-junk').createSync();
      expect(await library.list(), hasLength(1));
    });
  });

  group('StarDictLookupProvider', () {
    test('id, info and one raw sense per article', () async {
      final dictionary = await importPlain();
      final provider = library.providerFor(dictionary);
      addTearDown(provider.close);
      expect(provider.id, const ProviderId('stardict.test-dictionary'));
      expect(provider.info.name, 'Test dictionary');
      expect(provider.info.isOnline, isFalse);
      expect(provider.info.modes, {LookupMode.enRu});
      final result = await provider.lookup(_q('apple'));
      expect(result.senses, const [Sense(text: 'яблоко')]);
    });

    test('homographs give one sense each, exact spelling first', () async {
      final provider = library.providerFor(await importPlain());
      addTearDown(provider.close);
      final result = await provider.lookup(_q('bank'));
      expect(result.senses.map((s) => s.text), ['банк', 'берег']);
    });

    test('matching ignores case, outer and repeated spaces', () async {
      final provider = library.providerFor(await importPlain());
      addTearDown(provider.close);
      final result = await provider.lookup(_q('  APPLE '));
      expect(result.senses.single.text, 'яблоко');
    });

    test('HTML articles are returned raw', () async {
      final base = buildStarDict([
        const FixtureEntry('go', '<b>go</b> &amp; run'),
      ], sameTypeSequence: 'h').writeTo(source, 'h');
      final provider = library.providerFor(await library.import(files(base)));
      addTearDown(provider.close);
      final result = await provider.lookup(_q('go'));
      expect(result.senses.single.text, '<b>go</b> &amp; run');
    });

    test('an entry with an empty article is not found', () async {
      final provider = library.providerFor(await importPlain());
      addTearDown(provider.close);
      await expectLater(
        provider.lookup(_q('empty')),
        throwsA(isA<LookupNotFound>()),
      );
    });

    test('a mode the dictionary does not serve is unavailable', () async {
      final provider = library.providerFor(await importPlain());
      addTearDown(provider.close);
      await expectLater(
        provider.lookup(_q('apple', mode: LookupMode.enEn)),
        throwsA(isA<ProviderUnavailable>()),
      );
    });

    test('a removed dictionary becomes unavailable after close', () async {
      final dictionary = await importPlain();
      final provider = library.providerFor(dictionary);
      await provider.lookup(_q('apple'));
      provider.close();
      await library.remove(dictionary.id);
      await expectLater(
        provider.lookup(_q('apple')),
        throwsA(isA<ProviderUnavailable>()),
      );
    });

    test('close is safe before any lookup and can be repeated', () async {
      final provider = library.providerFor(await importPlain())
        ..close()
        ..close();
      final result = await provider.lookup(_q('apple'));
      expect(result.senses, isNotEmpty);
      provider.close();
    });

    test('a lookup in a 100 000 word dictionary takes under 10 ms', () async {
      final entries = [
        for (var i = 0; i < 100000; i++)
          FixtureEntry('word${i.toString().padLeft(6, '0')}', 'article $i'),
      ];
      final base = buildStarDict(entries).writeTo(source, 'big');
      final dictionary = await library.import(files(base));
      expect(dictionary.wordCount, 100000);
      final provider = library.providerFor(dictionary);
      addTearDown(provider.close);
      await provider.lookup(_q('word000000')); // loads the index

      final watch = Stopwatch();
      var slowest = Duration.zero;
      for (var i = 0; i < 200; i++) {
        final word = 'WORD${((i * 499) % 100000).toString().padLeft(6, '0')}';
        watch
          ..reset()
          ..start();
        final result = await provider.lookup(_q(word));
        watch.stop();
        expect(result.senses, hasLength(1));
        if (watch.elapsed > slowest) slowest = watch.elapsed;
      }
      printOnFailure('slowest lookup: $slowest');
      expect(slowest, lessThan(const Duration(milliseconds: 10)));
    });
  });
}
