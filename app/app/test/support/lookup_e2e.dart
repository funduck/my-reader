import 'dart:convert';
import 'dart:io';

import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:my_reader_app/bootstrap.dart';
import 'package:my_reader_app/router.dart';
import 'package:packs_http/packs_http.dart';
import 'package:reader_api/reader_api.dart';
import 'package:storage_drift/storage_drift.dart';

import 'pack_fixtures.dart';

/// Parts of the end-to-end lookup scenario (T-048) shared by the
/// `integration_test` (real engine, macOS) and the widget test (fake engine).
///
/// Everything between the engine and the stores is the real code: the reader
/// screen, the presenter, the sheet, `LookupSelection`, the Wiktionary
/// provider over `HttpPackStore` and the drift database.

/// Id of the fixture book.
const fixtureBookId = BookId('b1');

/// The only paragraph of the fixture book.
const fixtureParagraph = 'Child, come here.';

/// A sense of the fixture `en-en` entry `child`, as the sheet shows it.
const fixtureDefinition = 'A young human being.';

/// An [http.Client] that fails on every request and counts them.
///
/// Passed to `HttpPackStore` so that the test proves the lookup never goes to
/// the network.
class OfflineClient extends http.BaseClient {
  /// Requests tried so far.
  final List<Uri> attempts = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    attempts.add(request.url);
    throw http.ClientException('offline', request.url);
  }
}

/// Copies the embedded fixture packs (`en-en`, `en-forms`, `en-levels`) into a
/// new temporary directory and writes `packs.json` like `HttpPackStore` does.
///
/// [only] limits the packs; [enEnFile] replaces `en-en` by a copy of that
/// file (the real pack of U-3).
Directory installPacks({Set<String>? only, String? enEnFile}) {
  final dir = Directory.systemTemp.createTempSync('my-reader-packs');
  addTearDown(() => dir.deleteSync(recursive: true));
  final index = <String, String>{};
  for (final entry in packFixturesBase64.entries) {
    if (only != null && !only.contains(entry.key)) continue;
    final target = File('${dir.path}/${entry.key}.sqlite');
    if (entry.key == 'en-en' && enEnFile != null) {
      File(enEnFile).copySync(target.path);
    } else {
      target.writeAsBytesSync(base64Decode(entry.value));
    }
    index[entry.key] = '20260101.1';
  }
  File('${dir.path}/$packsIndexName')
      .writeAsStringSync(jsonEncode({'packs': index}));
  return dir;
}

/// Everything a scenario needs besides the engine.
class LookupFixture {
  new _(this.database, this.packsDir, this.client, this.adapter);

  /// Creates the fixture: in-memory drift, installed packs, offline client.
  static Future<LookupFixture> create({String? enEnFile}) async {
    final database = openInMemory();
    final adapter = FakeBookFormatAdapter()
      ..register(
        '/x/b1.epub',
        const BookMetadata(title: 'Dune'),
        chapters: [fixtureParagraph],
      );
    await database.bookRepository.save(
      Book(
        id: fixtureBookId,
        metadata: const BookMetadata(title: 'Dune'),
        format: BookFormat.epub,
        filePath: '/x/b1.epub',
        contentHash: 'h',
        addedAt: DateTime.utc(2024),
      ),
    );
    final dir = installPacks(
      only: enEnFile == null ? null : {'en-en'},
      enEnFile: enEnFile,
    );
    return LookupFixture._(database, dir, OfflineClient(), adapter);
  }

  /// The drift database of the app.
  final AppDatabase database;

  /// Directory of the installed packs.
  final Directory packsDir;

  /// The client that fails on any request.
  final OfflineClient client;

  /// Adapter that serves the fixture book.
  final FakeBookFormatAdapter adapter;

  /// Overrides of the app: real lookup chain, offline pack store, drift.
  List<Override> overrides({
    required ReaderEngineFactory engine,
    String? initialLocation,
  }) => [
    // Not `buildOverrides()`: it already overrides `packStoreProvider`.
    clockProvider.overrideWithValue(const SystemClock()),
    idGeneratorProvider.overrideWithValue(CounterIdGenerator()),
    ...buildLookupOverrides(packsDir.path),
    // Offline: the store may only look at the files, any request fails.
    packStoreProvider.overrideWith((ref) {
      final store = HttpPackStore(
        baseUri: Uri.parse('http://offline.invalid'),
        directory: packsDir,
        client: client,
      );
      ref.onDispose(store.close);
      return store;
    }),
    bookRepositoryProvider.overrideWithValue(database.bookRepository),
    progressRepositoryProvider.overrideWithValue(database.progressRepository),
    profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
    lookupJournalProvider.overrideWithValue(database.lookupJournal),
    termRepositoryProvider.overrideWithValue(database.termRepository),
    cheatSheetLogProvider.overrideWithValue(database.cheatSheetLog),
    bookFormatsProvider.overrideWithValue([adapter]),
    readerEngineFactoryProvider.overrideWithValue(engine),
    routerProvider.overrideWith(
      (ref) => createRouter(
        initialLocation: initialLocation ?? Routes.readerAt('b1'),
      ),
    ),
  ];
}

/// The journal of the app, newest first.
Future<List<LookupEvent>> journalOf(LookupFixture fixture) =>
    fixture.database.lookupJournal.watch().first;

/// The terms of the app.
Future<List<Term>> termsOf(LookupFixture fixture) =>
    fixture.database.termRepository.watchAll().first;

/// Checks the journal and the terms after [taps] lookups of `child`.
///
/// [sentence] is what the engine reported for the tap. Each journal event has
/// the `Locator` of the book and the sentence; the term counts the lookups.
Future<void> expectLookups(
  LookupFixture fixture, {
  required int taps,
  required String sentence,
}) async {
  final events = await journalOf(fixture);
  expect(events, hasLength(taps));
  for (final event in events) {
    expect(event.query.text.toLowerCase(), 'child');
    expect(event.query.locator?.book, fixtureBookId);
    expect(event.query.sentence, sentence);
    expect(event.result.senses, isNotEmpty);
  }
  final terms = await termsOf(fixture);
  expect(terms, hasLength(1));
  expect(terms.single.normalized, 'child');
  expect(terms.single.lookupCount, taps);
  expect(terms.single.eventIds, hasLength(taps));
  expect(fixture.client.attempts, isEmpty, reason: 'the lookup is offline');
}

/// Unmounts the app and lets drift close its streams: the reader's word
/// highlights (T-119) cancel their drift subscriptions one after another,
/// and drift closes each on a zero-duration timer.
Future<void> unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 1));
  }
}
