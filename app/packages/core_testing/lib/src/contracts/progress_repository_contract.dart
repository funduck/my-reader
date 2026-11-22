import 'dart:async';

import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:test/test.dart';

ReadingProgress _progress(String book, double progression, DateTime at) =>
    ReadingProgress(
      locator: Locator(
        book: BookId(book),
        chapter: const ChapterRef(href: 'c1.xhtml', index: 0),
        progression: progression,
      ),
      percent: progression,
      updatedAt: at,
    );

/// Behaviour every [ProgressRepository] must have.
///
/// [create] returns a fresh, empty repository for each test.
void progressRepositoryContract(
  FutureOr<ProgressRepository> Function() create,
) {
  group('ProgressRepository contract', () {
    late ProgressRepository repo;
    const a = BookId('a');
    const b = BookId('b');

    setUp(() async => repo = await create());

    test('get returns null if the book was never read', () async {
      expect(await repo.get(a), isNull);
    });

    test('save then get returns equal progress', () async {
      final p = _progress('a', 0.25, DateTime.utc(2024));
      await repo.save(p);
      expect(await repo.get(a), p);
    });

    test('save replaces the previous progress of the same book', () async {
      await repo.save(_progress('a', 0.25, DateTime.utc(2024)));
      final later = _progress('a', 0.5, DateTime.utc(2024, 2));
      await repo.save(later);
      expect(await repo.get(a), later);
    });

    test('progress of different books does not mix', () async {
      final pa = _progress('a', 0.1, DateTime.utc(2024));
      final pb = _progress('b', 0.9, DateTime.utc(2024));
      await repo.save(pa);
      await repo.save(pb);
      expect(await repo.get(a), pa);
      expect(await repo.get(b), pb);
    });

    test('watch emits null first, then every change of that book', () async {
      final emitted = <ReadingProgress?>[];
      final sub = repo.watch(a).listen(emitted.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(emitted, [null]);

      final p = _progress('a', 0.3, DateTime.utc(2024));
      await repo.save(p);
      await repo.save(_progress('b', 0.8, DateTime.utc(2024)));
      await pumpEventQueue();
      expect(emitted, [null, p]);
    });
  });
}
