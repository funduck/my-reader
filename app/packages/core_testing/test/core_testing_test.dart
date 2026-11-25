import 'dart:async';
import 'dart:typed_data';

import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:test/test.dart';

const _pid = ProviderId('fake');

LookupQuery _query(String text, {LookupMode mode = LookupMode.enEn}) =>
    LookupQuery(text: text, mode: mode);

FakeLookupProvider _provider({
  Duration delay = Duration.zero,
  LookupFailure? failure,
}) => FakeLookupProvider(
  id: _pid,
  delay: delay,
  failure: failure,
  answers: const {
    'word': LookupResult(
      provider: _pid,
      senses: [Sense(text: 'a unit of language')],
    ),
  },
);

void main() {
  // Fakes pass the same suites as real adapters (T-006 done criterion).
  group('FakeBookRepository', () {
    bookRepositoryContract(FakeBookRepository.new);
  });
  group('FakeProgressRepository', () {
    progressRepositoryContract(FakeProgressRepository.new);
  });
  group('FakeCheatSheetLog', () {
    cheatSheetLogContract(FakeCheatSheetLog.new);
  });
  group('FakeSecretStore', () {
    secretStoreContract(FakeSecretStore.new);
  });
  group('FakeProfileRepository', () {
    profileRepositoryContract(FakeProfileRepository.new);
  });
  group('FakeTermRepository', () {
    termRepositoryContract(FakeTermRepository.new);
  });
  group('FakeLookupJournal', () {
    lookupJournalContract(FakeLookupJournal.new);
  });
  group('FakePhraseJournal', () {
    phraseJournalContract(FakePhraseJournal.new);
  });
  group('FakeLookupProvider', () {
    lookupProviderContract(
      _provider,
      known: _query('word'),
      unknown: _query('zzz'),
      createUnavailable: () =>
          _provider(failure: const ProviderUnavailable('offline')),
    );
  });
  group('FakeBookFormatAdapter', () {
    const good = '/books/good.epub';
    const meta = BookMetadata(
      title: 'Good',
      author: 'An Author',
      language: 'en',
    );
    formatAdapterContract(
      () =>
          FakeBookFormatAdapter()
            ..register(good, meta, chapters: ['One.\n\nTwo.', 'Three.']),
      const FormatFixtures(
        valid: [BookFixture(path: good, metadata: meta, minChapters: 2)],
        invalid: ['/books/broken.epub', '/books/missing.epub'],
      ),
    );
  });

  group('FakeClock', () {
    test('stands still, advances and sets on demand', () {
      final clock = FakeClock(DateTime.utc(2024, 5, 2));
      expect(clock.now(), DateTime.utc(2024, 5, 2));
      expect(clock.now(), DateTime.utc(2024, 5, 2));
      clock.advance(const Duration(hours: 2));
      expect(clock.now(), DateTime.utc(2024, 5, 2, 2));
      clock.time = DateTime.utc(2030);
      expect(clock.now(), DateTime.utc(2030));
    });

    test('has a fixed default start', () {
      expect(FakeClock().now(), DateTime.utc(2024));
    });
  });

  group('SeqIdGenerator', () {
    test('returns distinct ids in order', () {
      final gen = SeqIdGenerator();
      expect([gen.newId(), gen.newId(), gen.newId()], ['id1', 'id2', 'id3']);
    });

    test('uses the prefix', () {
      expect(SeqIdGenerator(prefix: 'ev-').newId(), 'ev-1');
    });
  });

  group('FakeLookupProvider scripting', () {
    test(
      'returns the scripted answer, case-insensitively, and records calls',
      () async {
        final p = _provider();
        final r = await p.lookup(_query(' Word '));
        expect(r.senses.single.text, 'a unit of language');
        expect(p.calls, [_query(' Word ')]);
      },
    );

    test('a missing answer is LookupNotFound', () async {
      await expectLater(
        _provider().lookup(_query('zzz')),
        throwsA(isA<LookupNotFound>()),
      );
    });

    test('the configured failure is thrown for every text', () async {
      final p = _provider(failure: const ProviderUnavailable('x'));
      await expectLater(
        p.lookup(_query('word')),
        throwsA(isA<ProviderUnavailable>()),
      );
      p.failure = null;
      expect((await p.lookup(_query('word'))).senses, isNotEmpty);
    });

    test('delay holds the answer back', () async {
      final p = _provider(delay: const Duration(milliseconds: 50));
      var done = false;
      final future = p.lookup(_query('word')).whenComplete(() => done = true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(done, isFalse);
      await future;
      expect(done, isTrue);
    });

    test('cancel during the delay throws CancelledException', () async {
      final p = _provider(delay: const Duration(milliseconds: 30));
      final cancel = CancelToken();
      final future = p.lookup(_query('word'), cancel: cancel);
      cancel.cancel();
      await expectLater(future, throwsA(isA<CancelledException>()));
    });

    test('supports follows the modes of info', () {
      final p = FakeLookupProvider(
        id: _pid,
        info: const ProviderInfo(
          name: 'EN only',
          isOnline: false,
          modes: {LookupMode.enEn},
        ),
      );
      expect(p.supports(LookupMode.enEn), isTrue);
      expect(p.supports(LookupMode.enRu), isFalse);
    });
  });

  group('FakeOpenedBook', () {
    test('builds spine, toc and paragraphs from strings', () async {
      final book = FakeOpenedBook(
        chapters: ['First para.\n\nSecond para.', 'Only para.'],
        titles: ['Intro', 'Ending'],
      );
      expect(book.spine.map((c) => c.index), [0, 1]);
      expect(book.toc.map((e) => e.title), ['Intro', 'Ending']);
      expect(book.toc[1].chapter, book.spine[1]);
      final doc = await book.chapter(book.spine[0]);
      expect(
        doc,
        const ContentDocument([
          ParagraphBlock([TextInline('First para.')]),
          ParagraphBlock([TextInline('Second para.')]),
        ]),
      );
    });

    test('serves resources and rejects unknown ones', () async {
      final book = FakeOpenedBook(
        chapters: ['x'],
        resources: {
          'cover.png': Uint8List.fromList([1, 2, 3]),
        },
      );
      expect(await book.resource('cover.png'), [1, 2, 3]);
      await expectLater(
        book.resource('nope.png'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a chapter that is not in the spine', () async {
      final book = FakeOpenedBook(chapters: ['x']);
      await expectLater(
        book.chapter(const ChapterRef(href: 'other.xhtml', index: 0)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('is unusable after close', () async {
      final book = FakeOpenedBook(chapters: ['x']);
      await book.close();
      expect(book.isClosed, isTrue);
      await expectLater(
        book.chapter(book.spine.first),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('FakePackStore', () {
    const entry = PackManifestEntry(
      id: 'en-en',
      version: '2',
      sizeBytes: 10,
      sha256: 'ab',
    );

    test(
      'download installs the offered version and reports progress',
      () async {
        final store = FakePackStore(offered: [entry]);
        expect(await store.pathOf('en-en'), isNull);
        final seen = <double>[];
        final pack = await store.download('en-en', seen.add);
        expect(pack, const InstalledPack(id: 'en-en', version: '2'));
        expect(seen.first, 0);
        expect(seen.last, 1);
        expect(await store.installed(), [pack]);
        expect(await store.pathOf('en-en'), isNotNull);
      },
    );

    test('a failed download keeps the installed version', () async {
      final store = FakePackStore(
        offered: [entry],
        installedPacks: [const InstalledPack(id: 'en-en', version: '1')],
      )..error = const SocketLikeError();
      await expectLater(
        store.download('en-en', (_) {}),
        throwsA(isA<SocketLikeError>()),
      );
      expect(await store.installed(), [
        const InstalledPack(id: 'en-en', version: '1'),
      ]);
      await expectLater(store.manifest(), throwsA(isA<SocketLikeError>()));
    });

    test('manifest works and remove is idempotent', () async {
      final store = FakePackStore(
        offered: [entry],
        installedPacks: [const InstalledPack(id: 'en-en', version: '1')],
      );
      expect(await store.manifest(), [entry]);
      await store.remove('en-en');
      await store.remove('en-en');
      expect(await store.installed(), isEmpty);
      expect(await store.pathOf('en-en'), isNull);
    });

    test('downloading an unoffered pack fails', () async {
      await expectLater(
        FakePackStore().download('x', (_) {}),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('FakeBookRepository vs progress', () {
    test('remove does not touch progress (documented limitation)', () async {
      // The fake repositories are independent; cascade is storage's job.
      final books = FakeBookRepository();
      final progress = FakeProgressRepository();
      await progress.save(
        ReadingProgress(
          locator: const Locator(
            book: BookId('a'),
            chapter: ChapterRef(href: 'c.xhtml', index: 0),
            progression: 0.1,
          ),
          percent: 0.1,
          updatedAt: DateTime.utc(2024),
        ),
      );
      await books.remove(const BookId('a'));
      expect(await progress.get(const BookId('a')), isNotNull);
    });
  });
}

/// Stand-in for a network error in pack store tests.
class SocketLikeError implements Exception {
  const new();
}
