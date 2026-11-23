import 'dart:async';
import 'dart:io';

import 'package:core/application.dart' show LevelCheatSheetGenerator;
import 'package:core/domain_books.dart' show Locator;
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:features_common/features_common.dart';
import 'package:features_library/features_library.dart';
import 'package:features_reader/features_reader.dart';
import 'package:features_settings/features_settings.dart'
    show backgroundsDirectoryProvider, fontsDirectoryProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:format_epub/format_epub.dart';
import 'package:go_router/go_router.dart';
import 'package:levels_cefr/levels_cefr.dart';
import 'package:logging/logging.dart';
import 'package:lookup_sheet/lookup_sheet.dart';
import 'package:lookup_stardict/lookup_stardict.dart';
import 'package:lookup_wiktionary/lookup_wiktionary.dart'
    show WiktionaryLookupProvider;
import 'package:material_ui/material_ui.dart';
import 'package:packs_http/packs_http.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader_simple/reader_simple.dart';
import 'package:secrets_os/secrets_os.dart';
import 'package:storage_drift/storage_drift.dart';
import 'package:text_en/text_en.dart';

import 'app.dart';
import 'logging.dart';
import 'router.dart';

/// Overrides of the port providers: the only place where concrete
/// implementations are chosen (docs/Architecture-app.md, section 8).
///
/// Ports that have no implementation yet are not overridden, so reading them
/// throws `PortNotWiredError`. Other tasks add their lines here.
List<Override> buildOverrides() => [
  clockProvider.overrideWithValue(const SystemClock()),
  idGeneratorProvider.overrideWithValue(CounterIdGenerator()),
  packStoreProvider.overrideWith(_buildPackStore),
];

/// Overrides that need the device: the drift database file and the directory
/// of imported books, both in the application support directory, plus the
/// repositories and format adapters on top of them, and the reader engine
/// (kept here so that tests of `buildOverrides` can supply their own).
///
/// Call once before `runApp` and pass `[...buildOverrides(), ...these]`.
Future<List<Override>> buildDeviceOverrides() async {
  final support = await getApplicationSupportDirectory();
  await support.create(recursive: true);
  final database = openDatabase('${support.path}/my_reader.sqlite');
  final packsDirPath = '${support.path}/packs';
  final dictionaries = await StarDictDictionaries.open(
    StarDictLibrary(directory: '${support.path}/dictionaries'),
  );
  // The chosen font is registered before the first frame of the reader.
  final font = (await database.profileRepository.get()).display.font;
  if (font != null) await loadUserFont(font);
  return [
    bookRepositoryProvider.overrideWithValue(database.bookRepository),
    progressRepositoryProvider.overrideWithValue(database.progressRepository),
    profileRepositoryProvider.overrideWithValue(database.profileRepository),
    lookupJournalProvider.overrideWithValue(database.lookupJournal),
    termRepositoryProvider.overrideWithValue(database.termRepository),
    bookFormatsProvider.overrideWithValue(const [EpubFormatAdapter()]),
    booksDirectoryProvider.overrideWithValue('${support.path}/books'),
    backgroundsDirectoryProvider.overrideWithValue(
      '${support.path}/backgrounds',
    ),
    fontsDirectoryProvider.overrideWithValue('${support.path}/fonts'),
    secretStoreProvider.overrideWithValue(OsSecretStore()),
    ...buildLookupOverrides(packsDirPath, dictionaries: dictionaries),
    // The engine needs only sentence bounds and lemmas from the analyzer.
    readerEngineFactoryProvider.overrideWith(
      (ref) =>
          () => SimpleReaderEngine(analyzer: ref.watch(textAnalyzerProvider)),
    ),
  ];
}

/// Overrides of the tap-to-lookup chain: text analyzer, level dictionary,
/// dictionary providers, the lookup sheet presenter and the cheat sheet
/// generator.
///
/// Packs are read from [packsDirPath] (the catalog of installed packs) as
/// soon as they appear there. Separate from [buildDeviceOverrides] so that a
/// test can wire the same chain without `path_provider`; it can also pass its
/// own dictionary [providers] instead of the pack-backed ones.
///
/// With [dictionaries] the user's StarDict dictionaries are added to the
/// providers and `dictionaryLibraryProvider` is wired to it.
List<Override> buildLookupOverrides(
  String packsDirPath, {
  List<LookupProvider> Function(Ref ref)? providers,
  StarDictDictionaries? dictionaries,
}) => [
  textAnalyzerProvider.overrideWithValue(
    EnglishTextAnalyzer(lemmatizer: PackFormsLemmatizer(packsDirPath)),
  ),
  levelDictionaryProvider.overrideWithValue(PackLevelDictionary(packsDirPath)),
  lookupProvidersProvider.overrideWith(
    providers ?? (ref) => _buildLookupProviders(ref, dictionaries),
  ),
  if (dictionaries != null)
    dictionaryLibraryProvider.overrideWithValue(dictionaries),
  lookupPresenterProvider.overrideWith(_buildLookupPresenter),
  cheatSheetGeneratorProvider.overrideWith(_buildCheatSheetGenerator),
];

/// Cheat sheet generator over the analyzer and the level dictionary of the
/// app (the same instances the lookup sheet uses, so one `en-levels` file is
/// open). Level and piece size come from the profile on every build of a
/// sheet, so changes in settings apply without a restart.
CheatSheetGenerator _buildCheatSheetGenerator(Ref ref) =>
    LevelCheatSheetGenerator(
      analyzer: ref.watch(textAnalyzerProvider),
      levels: ref.watch(levelDictionaryProvider),
    );

/// Dictionary providers: `en-en` Wiktionary over the installed packs, then
/// the user's StarDict dictionaries.
///
/// The lemma hook uses the analyzer of the app, so inflected forms find their
/// headword. The list is rebuilt when [dictionaries] reports an import or a
/// removal; the old providers are closed then.
List<LookupProvider> _buildLookupProviders(
  Ref ref,
  StarDictDictionaries? dictionaries,
) {
  final analyzer = ref.watch(textAnalyzerProvider);
  final provider = WiktionaryLookupProvider(
    packStore: ref.watch(packStoreProvider),
    lemmas: (text) => [analyzer.lemma(text)],
  );
  ref.onDispose(provider.close);
  if (dictionaries == null) return [provider];
  void changed() => ref.invalidateSelf();
  dictionaries.revision.addListener(changed);
  final imported = dictionaries.createProviders();
  ref.onDispose(() {
    dictionaries.revision.removeListener(changed);
    for (final p in imported) {
      p.close();
    }
  });
  return [provider, ...imported];
}

/// [DictionaryLibrary] over a [StarDictLibrary].
///
/// `StarDictLibrary` has no change stream, so this class keeps the list of
/// dictionaries and bumps [revision] after every import and removal; the
/// lookup providers are rebuilt on it. A provider is closed before its
/// dictionary is removed.
class StarDictDictionaries implements DictionaryLibrary {
  new _(this._library, this._dictionaries);

  /// Opens the library and reads its dictionaries.
  static Future<StarDictDictionaries> open(StarDictLibrary library) async =>
      StarDictDictionaries._(library, await library.list());

  final StarDictLibrary _library;
  List<StarDictDictionary> _dictionaries;
  Map<String, StarDictLookupProvider> _live = {};

  /// Grows by one after every import and removal.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Builds a provider for every dictionary; the caller closes them.
  List<StarDictLookupProvider> createProviders() {
    final providers = {
      for (final d in _dictionaries) d.id: _library.providerFor(d),
    };
    _live = providers;
    return providers.values.toList();
  }

  ImportedDictionary _describe(StarDictDictionary d) => ImportedDictionary(
    id: d.id,
    name: d.name,
    mode: d.mode,
    wordCount: d.wordCount,
    providerId: d.providerId,
  );

  @override
  Future<List<ImportedDictionary>> list() async => [
    for (final d in await _library.list()) _describe(d),
  ];

  @override
  Future<ImportedDictionary> import(List<String> files, LookupMode mode) async {
    final dictionary = await _library.import(files, mode: mode);
    _dictionaries = await _library.list();
    revision.value++;
    return _describe(dictionary);
  }

  @override
  Future<bool> remove(String id) async {
    _live.remove(id)?.close();
    final existed = await _library.remove(id);
    _dictionaries = await _library.list();
    revision.value++;
    return existed;
  }
}

/// Opens the lookup sheet for a word the reader reports; the direction is the
/// default of the profile, the sheet's "settings" button goes to settings.
LookupPresenter _buildLookupPresenter(Ref ref) {
  return (
    BuildContext context, {
    required String text,
    required Locator at,
    required String sentence,
  }) async {
    final profile = await ref.read(profileRepositoryProvider).get();
    if (!context.mounted) return;
    await showLookupSheet(
      context,
      LookupQuery(
        text: text,
        mode: profile.mode,
        sentence: sentence,
        locator: at,
      ),
      onOpenSettings: () => context.push(Routes.settings),
    );
  };
}

/// Service address used when the profile has none.
const defaultServiceUrl = 'http://localhost:8080';

/// Address of the service from the profile, `null` while the profile is
/// not loaded or has no address.
///
/// Emits only when the address itself changes.
final StreamProvider<String?> serviceUrlProvider = StreamProvider<String?>(
  (ref) =>
      ref.watch(profileRepositoryProvider).watch().map((p) => p.serviceUrl),
);

/// Builds the pack store for the current service address.
///
/// The provider depends on [serviceUrlProvider], so a new address creates a
/// new store (the old one is closed) and everything that watches
/// `packStoreProvider` rebuilds with it.
PackStore _buildPackStore(Ref ref) {
  final url = ref.watch(serviceUrlProvider).value;
  final store = LazyHttpPackStore(
    baseUri: Uri.parse(url ?? defaultServiceUrl),
    directory: packsDirectory,
  );
  ref.onDispose(store.close);
  return store;
}

final Logger _packLog = Logger('PackBacked');

/// Path of the installed pack [id] in the catalog [directory], `null` if the
/// pack file is not there (layout of `HttpPackStore`: `<dir>/<id>.sqlite`).
String? _installedPackPath(String directory, String id) {
  final path = '$directory/$id.sqlite';
  return File(path).existsSync() ? path : null;
}

/// [Lemmatizer] over the `en-forms` pack that opens it on first use after it
/// is installed; before that it only lower-cases (like no lemmatizer).
class PackFormsLemmatizer implements Lemmatizer {
  /// Creates a lemmatizer reading the pack from the catalog [directory].
  new(this.directory);

  /// Catalog of installed packs.
  final String directory;

  Lemmatizer? _inner;

  @override
  String lemma(String word, {String? pos}) {
    var inner = _inner;
    if (inner == null) {
      final path = _installedPackPath(directory, 'en-forms');
      if (path != null) {
        try {
          inner = _inner = FormsLemmatizer.open(path);
        } on Object catch (e, s) {
          _packLog.warning('Opening en-forms failed', e, s);
        }
      }
    }
    return inner?.lemma(word, pos: pos) ?? normalizeKey(word);
  }
}

/// [LevelDictionary] over the `en-levels` pack that opens it on first use
/// after it is installed; before that every word is unknown.
class PackLevelDictionary implements LevelDictionary {
  /// Creates a dictionary reading the pack from the catalog [directory].
  new(this.directory);

  /// Catalog of installed packs.
  final String directory;

  CefrLevelDictionary? _inner;

  @override
  WordLevel levelOf(String lemma, {String? pos}) {
    var inner = _inner;
    if (inner == null) {
      final path = _installedPackPath(directory, 'en-levels');
      if (path != null) {
        try {
          inner = _inner = CefrLevelDictionary.fromPath(path);
        } on Object catch (e, s) {
          _packLog.warning('Opening en-levels failed', e, s);
        }
      }
    }
    return inner?.levelOf(lemma, pos: pos) ??
        const WordLevel(CefrLevel.unknown);
  }
}

/// Catalog of installed packs: `<application support>/packs`.
Future<Directory> packsDirectory() async {
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}${Platform.pathSeparator}packs');
}

/// Builds the root widget with all providers wired.
Widget bootstrap({List<Override>? overrides}) {
  return ProviderScope(
    overrides: overrides ?? buildOverrides(),
    observers: const [LoggingProviderObserver()],
    child: const MyReaderApp(),
  );
}

/// [Clock] backed by the system time.
class SystemClock implements Clock {
  /// Creates the clock.
  const new();

  @override
  DateTime now() => DateTime.now();
}

/// [IdGenerator] that combines the start time with a counter.
///
/// Placeholder until a real generator (uuid) is chosen.
class CounterIdGenerator implements IdGenerator {
  /// Creates the generator.
  new() : _prefix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  final String _prefix;
  int _next = 0;

  @override
  String newId() => '$_prefix-${(_next++).toRadixString(36)}';
}

/// [HttpPackStore] that creates its directory and itself on first use.
///
/// `path_provider` is asynchronous, but providers are synchronous; the
/// directory is therefore resolved on the first call.
class LazyHttpPackStore implements PackStore {
  /// Creates a store for the service at [baseUri]; `directory` resolves the
  /// pack catalog.
  new({required this.baseUri, required this._directory});

  /// Service root.
  final Uri baseUri;

  final Future<Directory> Function() _directory;
  Future<HttpPackStore>? _inner;
  bool _closed = false;

  Future<HttpPackStore> _store() => _inner ??= _create();

  Future<HttpPackStore> _create() async {
    final dir = await _directory();
    await dir.create(recursive: true);
    final store = HttpPackStore(baseUri: baseUri, directory: dir);
    if (_closed) store.close();
    return store;
  }

  /// Closes the underlying store, if it was created.
  void close() {
    _closed = true;
    final inner = _inner;
    if (inner != null) {
      unawaited(inner.then((s) => s.close(), onError: (Object _) {}));
    }
  }

  @override
  Future<List<PackManifestEntry>> manifest() =>
      _store().then((s) => s.manifest());

  @override
  Future<List<InstalledPack>> installed() =>
      _store().then((s) => s.installed());

  @override
  Future<InstalledPack> download(String id, PackProgress onProgress) =>
      _store().then((s) => s.download(id, onProgress));

  @override
  Future<String?> pathOf(String id) => _store().then((s) => s.pathOf(id));

  @override
  Future<void> remove(String id) => _store().then((s) => s.remove(id));
}
