import 'dart:async';

import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:test/test.dart';

Book _book(String id, {String hash = 'h', DateTime? addedAt, String? title}) =>
    Book(
      id: BookId(id),
      metadata: BookMetadata(title: title ?? 'Title $id'),
      format: BookFormat.epub,
      filePath: '/books/$id.epub',
      contentHash: '$hash-$id',
      addedAt: addedAt ?? DateTime.utc(2024),
    );

/// Behaviour every [BookRepository] must have.
///
/// [create] returns a fresh, empty repository for each test; it may register
/// cleanup with `addTearDown`. Progress is not part of this contract.
void bookRepositoryContract(FutureOr<BookRepository> Function() create) {
  group('BookRepository contract', () {
    late BookRepository repo;

    setUp(() async => repo = await create());

    test('get returns null for an unknown id', () async {
      expect(await repo.get(const BookId('nope')), isNull);
    });

    test('save then get returns an equal book', () async {
      final book = _book('a');
      await repo.save(book);
      expect(await repo.get(book.id), book);
    });

    test('save with an existing id replaces the book', () async {
      await repo.save(_book('a', title: 'Old'));
      final updated = _book('a', title: 'New');
      await repo.save(updated);
      expect(await repo.get(const BookId('a')), updated);
      expect(await repo.watchAll().first, [updated]);
    });

    test('findByContentHash finds the book or returns null', () async {
      final book = _book('a', hash: 'x');
      await repo.save(book);
      await repo.save(_book('b', hash: 'y'));
      expect(await repo.findByContentHash(book.contentHash), book);
      expect(await repo.findByContentHash('missing'), isNull);
    });

    test('remove deletes the book; removing it again is harmless', () async {
      await repo.save(_book('a'));
      await repo.remove(const BookId('a'));
      expect(await repo.get(const BookId('a')), isNull);
      await repo.remove(const BookId('a'));
      expect(await repo.watchAll().first, isEmpty);
    });

    test('watchAll emits the current value first, newest book first', () async {
      final old = _book('old', addedAt: DateTime.utc(2024));
      final fresh = _book('new', addedAt: DateTime.utc(2025));
      await repo.save(old);
      await repo.save(fresh);
      expect(await repo.watchAll().first, [fresh, old]);
    });

    test('watchAll emits again after save and remove', () async {
      final emitted = <List<Book>>[];
      final sub = repo.watchAll().listen(emitted.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(emitted, [<Book>[]]);

      final book = _book('a');
      await repo.save(book);
      await pumpEventQueue();
      expect(emitted.last, [book]);

      await repo.remove(book.id);
      await pumpEventQueue();
      expect(emitted.last, isEmpty);
    });
  });
}
