import 'dart:io';

import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core_testing/core_testing.dart';
import 'package:storage_drift/storage_drift.dart';
import 'package:test/test.dart';

AppDatabase _inMemory() {
  final db = openInMemory();
  addTearDown(db.close);
  return db;
}

Locator _locator(String book) => Locator(
  book: BookId(book),
  chapter: const ChapterRef(href: 'OEBPS/ch1.xhtml#s2', index: 3),
  progression: 0.4,
  quote: TextQuote.fromText('Call me Ishmael. Some years ago', 14, 22),
  engineHint: 'offset:1234',
);

Book _book(String id) => Book(
  id: BookId(id),
  metadata: const BookMetadata(
    title: 'Moby-Dick',
    author: 'Herman Melville',
    language: 'en',
  ),
  format: BookFormat.fb2,
  filePath: '/books/$id.fb2',
  contentHash: 'hash-$id',
  addedAt: DateTime.utc(2024, 5, 6, 7, 8, 9, 10, 11),
);

void main() {
  bookRepositoryContract(() => _inMemory().bookRepository);
  progressRepositoryContract(() => _inMemory().progressRepository);
  profileRepositoryContract(() => _inMemory().profileRepository);
  lookupJournalContract(() => _inMemory().lookupJournal);
  termRepositoryContract(() => _inMemory().termRepository);
  phraseJournalContract(() => _inMemory().phraseJournal);

  group('storage_drift', () {
    test(
      'removing a book removes its progress and keeps other books',
      () async {
        final db = _inMemory();
        final books = db.bookRepository;
        final progress = db.progressRepository;
        await books.save(_book('a'));
        await books.save(_book('b'));
        await progress.save(
          ReadingProgress(
            locator: _locator('a'),
            percent: 0.4,
            updatedAt: DateTime.utc(2024),
          ),
        );
        final other = ReadingProgress(
          locator: _locator('b'),
          percent: 0.9,
          updatedAt: DateTime.utc(2024),
        );
        await progress.save(other);

        await books.remove(const BookId('a'));

        expect(await progress.get(const BookId('a')), isNull);
        expect(await progress.watch(const BookId('a')).first, isNull);
        expect(await progress.get(const BookId('b')), other);
        expect(await books.get(const BookId('b')), isNotNull);
      },
    );

    test('Locator with quote and engineHint survives a round trip', () async {
      final progress = _inMemory().progressRepository;
      final saved = ReadingProgress(
        locator: _locator('a'),
        percent: 0.4,
        updatedAt: DateTime.utc(2024, 1, 2, 3, 4, 5, 6, 7),
      );
      await progress.save(saved);
      final loaded = await progress.get(const BookId('a'));
      expect(loaded, saved);
      expect(loaded!.locator.quote, _locator('a').quote);
      expect(loaded.locator.engineHint, 'offset:1234');
    });

    test('book with all fields keeps microseconds and metadata', () async {
      final books = _inMemory().bookRepository;
      final book = _book('a');
      await books.save(book);
      expect(await books.get(book.id), book);
    });

    test('profile keeps scope, provider order and clears serviceUrl', () async {
      final repo = _inMemory().profileRepository;
      const full = UserProfile(
        scope: CheatSheetChapter(),
        providerOrder: [ProviderId('x'), ProviderId('y')],
        serviceUrl: 'http://host:1',
      );
      await repo.save(full);
      expect(await repo.get(), full);
      final cleared = full.copyWith(serviceUrl: () => null);
      await repo.save(cleared);
      expect((await repo.get()).serviceUrl, isNull);
    });

    test('data written to a file is there after reopening it', () async {
      final dir = Directory.systemTemp.createTempSync('storage_drift_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/app.sqlite';

      final first = openDatabase(path);
      await first.bookRepository.save(_book('a'));
      await first.progressRepository.save(
        ReadingProgress(
          locator: _locator('a'),
          percent: 0.4,
          updatedAt: DateTime.utc(2024),
        ),
      );
      await first.profileRepository.save(
        const UserProfile(level: CefrLevel.c1),
      );
      await first.close();

      final second = openDatabase(path);
      addTearDown(second.close);
      expect(await second.bookRepository.get(const BookId('a')), _book('a'));
      expect(await second.progressRepository.get(const BookId('a')), isNotNull);
      expect((await second.profileRepository.get()).level, CefrLevel.c1);
    });
  });
}
