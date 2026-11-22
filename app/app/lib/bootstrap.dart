import 'dart:async';
import 'dart:io';

import 'package:core/ports.dart';
import 'package:features_common/features_common.dart';
import 'package:features_library/features_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:format_epub/format_epub.dart';
import 'package:material_ui/material_ui.dart';
import 'package:packs_http/packs_http.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader_simple/reader_simple.dart';
import 'package:storage_drift/storage_drift.dart';
import 'package:text_en/text_en.dart';

import 'app.dart';
import 'logging.dart';

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
  return [
    bookRepositoryProvider.overrideWithValue(database.bookRepository),
    progressRepositoryProvider.overrideWithValue(database.progressRepository),
    profileRepositoryProvider.overrideWithValue(database.profileRepository),
    lookupJournalProvider.overrideWithValue(database.lookupJournal),
    termRepositoryProvider.overrideWithValue(database.termRepository),
    bookFormatsProvider.overrideWithValue(const [EpubFormatAdapter()]),
    booksDirectoryProvider.overrideWithValue('${support.path}/books'),
    // Sentence bounds need no lemmatizer; T-047 wires the pack-backed one.
    readerEngineFactoryProvider.overrideWithValue(
      () => SimpleReaderEngine(analyzer: const EnglishTextAnalyzer()),
    ),
  ];
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
