import 'dart:io';

import 'package:core/application.dart' show LevelCheatSheetGenerator;
import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:core_testing/fakes.dart';
import 'package:features_common/features_common.dart';
import 'package:features_library/features_library.dart';
import 'package:features_reader/features_reader.dart';
import 'package:features_settings/features_settings.dart'
    show backgroundsDirectoryProvider, fontsDirectoryProvider;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:lookup_sheet/lookup_sheet.dart';
import 'package:reader_simple/reader_simple.dart';
import 'package:text_en/text_en.dart';

import '../bootstrap.dart' show SystemClock, buildLookupPresenter;
import '../router.dart';
import 'demo_data.dart';
import 'scenarios.dart';

/// Overrides of every port for [scenario]: in-memory fakes seeded with the
/// demo data. Nothing touches the disk (except an empty temp directory for
/// files the settings could write), the network or the keychain.
///
/// Every call gives fresh state, so a scenario always starts the same way.
Future<List<Override>> buildDemoOverrides(DemoScenario scenario) async {
  final books = FakeBookRepository();
  await books.save(
    Book(
      id: demoBookId,
      metadata: const BookMetadata(
        title: demoBookTitle,
        author: 'Demo',
        language: 'en',
      ),
      format: BookFormat.epub,
      filePath: demoBookPath,
      contentHash: 'demo',
      addedAt: DateTime.utc(2026),
    ),
  );
  final formats = FakeBookFormatAdapter()
    ..register(
      demoBookPath,
      const BookMetadata(title: demoBookTitle),
      chapters: demoChapters,
    );
  const analyzer = EnglishTextAnalyzer();
  const levels = DemoLevelDictionary();
  final files = '${Directory.systemTemp.path}/my_reader_demo';
  return [
    clockProvider.overrideWithValue(const SystemClock()),
    idGeneratorProvider.overrideWithValue(SeqIdGenerator(prefix: 'demo-')),
    bookRepositoryProvider.overrideWithValue(books),
    progressRepositoryProvider.overrideWithValue(FakeProgressRepository()),
    profileRepositoryProvider.overrideWithValue(
      FakeProfileRepository(scenario.profile),
    ),
    lookupJournalProvider.overrideWithValue(FakeLookupJournal()),
    phraseJournalProvider.overrideWithValue(FakePhraseJournal()),
    termRepositoryProvider.overrideWithValue(FakeTermRepository()),
    packStoreProvider.overrideWithValue(FakePackStore()),
    textAnalyzerProvider.overrideWithValue(analyzer),
    levelDictionaryProvider.overrideWithValue(levels),
    cheatSheetGeneratorProvider.overrideWithValue(
      const LevelCheatSheetGenerator(analyzer: analyzer, levels: levels),
    ),
    bookFormatsProvider.overrideWithValue([formats]),
    lookupProvidersProvider.overrideWithValue([
      FakeLookupProvider(
        id: demoEnEnProvider,
        info: const ProviderInfo(
          name: 'Demo EN-EN',
          isOnline: false,
          modes: {LookupMode.enEn},
        ),
        answers: demoEnEnAnswers,
      ),
      FakeLookupProvider(
        id: demoEnRuProvider,
        info: const ProviderInfo(
          name: 'Demo EN-RU',
          isOnline: false,
          modes: {LookupMode.enRu},
        ),
        answers: demoEnRuAnswers,
      ),
    ]),
    phraseProviderProvider.overrideWithValue(
      FakeLookupProvider(
        id: demoPhraseProvider,
        info: const ProviderInfo(
          name: 'Demo phrases',
          isOnline: true,
          modes: {LookupMode.enRu},
        ),
        answers: const {
          demoPhrase: LookupResult(
            provider: demoPhraseProvider,
            senses: [Sense(text: demoPhraseTranslation)],
          ),
        },
      ),
    ),
    secretStoreProvider.overrideWithValue(
      FakeSecretStore({deeplApiKey: 'demo-key:fx'}),
    ),
    dictionaryLibraryProvider.overrideWithValue(const DemoDictionaryLibrary()),
    lookupPresenterProvider.overrideWith(buildLookupPresenter),
    readerEngineFactoryProvider.overrideWithValue(
      () => SimpleReaderEngine(analyzer: analyzer),
    ),
    booksDirectoryProvider.overrideWithValue('$files/books'),
    backgroundsDirectoryProvider.overrideWithValue('$files/backgrounds'),
    fontsDirectoryProvider.overrideWithValue('$files/fonts'),
    routerProvider.overrideWith((ref) {
      final router = createRouter(initialLocation: scenario.location);
      ref.onDispose(router.dispose);
      return router;
    }),
  ];
}

/// [LevelDictionary] over [demoLevels]; other words are unknown.
class DemoLevelDictionary implements LevelDictionary {
  /// Creates the dictionary.
  const new();

  @override
  WordLevel levelOf(String lemma, {String? pos}) =>
      WordLevel(demoLevels[lemma.toLowerCase()] ?? CefrLevel.unknown);
}

/// [DictionaryLibrary] without dictionaries; importing is not supported.
class DemoDictionaryLibrary implements DictionaryLibrary {
  /// Creates the library.
  const new();

  @override
  Future<List<ImportedDictionary>> list() async => const [];

  @override
  Future<ImportedDictionary> import(List<String> files, LookupMode mode) =>
      Future.error(UnsupportedError('No dictionary import in the demo'));

  @override
  Future<bool> remove(String id) async => false;
}
