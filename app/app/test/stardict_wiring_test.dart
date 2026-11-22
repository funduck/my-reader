import 'dart:io';

import 'package:core/domain_lookup.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup_stardict/lookup_stardict.dart';
import 'package:my_reader_app/bootstrap.dart';

import '../../packages/lookup_stardict/test/fixtures/build.dart';

/// The StarDict part of `bootstrap.dart`: the library port over
/// `StarDictLibrary` and the provider list that follows its changes.
void main() {
  late Directory tmp;
  late String sourceFiles;
  late StarDictDictionaries dictionaries;
  late ProviderContainer container;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('stardict_wiring');
    sourceFiles = buildStarDict(const [
      FixtureEntry('sand', 'песок'),
    ], bookName: 'Mini RU').writeTo('${tmp.path}/src', 'mini');
    dictionaries = await StarDictDictionaries.open(
      StarDictLibrary(directory: '${tmp.path}/dictionaries'),
    );
    container = ProviderContainer(
      overrides: [
        packStoreProvider.overrideWithValue(FakePackStore()),
        ...buildLookupOverrides(
          '${tmp.path}/packs',
          dictionaries: dictionaries,
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    tmp.deleteSync(recursive: true);
  });

  List<String> providerIds() => [
    for (final p in container.read(lookupProvidersProvider)) p.id.value,
  ];

  List<String> files() => [
    '$sourceFiles.ifo',
    '$sourceFiles.idx',
    '$sourceFiles.dict',
  ];

  test('without dictionaries only Wiktionary is registered', () {
    expect(providerIds(), ['wiktionary.en-en']);
    expect(container.read(dictionaryLibraryProvider), same(dictionaries));
  });

  test('import adds a provider and remove takes it away', () async {
    final library = container.read(dictionaryLibraryProvider);
    // Keep the provider list alive like the settings screen does.
    container.listen(lookupProvidersProvider, (_, _) {});

    final imported = await library.import(files(), LookupMode.enRu);
    expect(imported.id, 'mini-ru');
    expect(imported.providerId, const ProviderId('stardict.mini-ru'));
    expect(providerIds(), ['wiktionary.en-en', 'stardict.mini-ru']);
    expect([for (final d in await library.list()) d.name], ['Mini RU']);

    final provider = container
        .read(lookupProvidersProvider)
        .firstWhere((p) => p.id == imported.providerId);
    final result = await provider.lookup(
      const LookupQuery(text: 'sand', mode: LookupMode.enRu),
    );
    expect(result.senses.single.text, 'песок');

    expect(await library.remove('mini-ru'), isTrue);
    expect(providerIds(), ['wiktionary.en-en']);
    expect(Directory('${tmp.path}/dictionaries/mini-ru').existsSync(), isFalse);
    expect(await library.list(), isEmpty);
  });

  test('a bad import changes nothing', () async {
    final library = container.read(dictionaryLibraryProvider);
    await expectLater(
      library.import(['$sourceFiles.ifo'], LookupMode.enRu),
      throwsFormatException,
    );
    expect(providerIds(), ['wiktionary.en-en']);
  });

  test('dictionaries imported earlier are registered on start', () async {
    final library = StarDictLibrary(directory: '${tmp.path}/dictionaries');
    await library.import(files());
    final again = await StarDictDictionaries.open(library);
    final other = ProviderContainer(
      overrides: [
        packStoreProvider.overrideWithValue(FakePackStore()),
        ...buildLookupOverrides('${tmp.path}/packs', dictionaries: again),
      ],
    );
    addTearDown(other.dispose);
    expect(
      [for (final p in other.read(lookupProvidersProvider)) p.id.value],
      ['wiktionary.en-en', 'stardict.mini-ru'],
    );
  });
}
