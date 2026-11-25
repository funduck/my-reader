import 'dart:async';

import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:test/test.dart';

CheatSheetSnapshot _snapshot(
  String book,
  DateTime at, {
  List<String> lemmas = const ['spice', 'flow'],
}) => CheatSheetSnapshot(book: BookId(book), shownAt: at, lemmas: lemmas);

/// Behaviour every [CheatSheetLog] must have.
///
/// [create] returns a fresh, empty log for each test.
void cheatSheetLogContract(FutureOr<CheatSheetLog> Function() create) {
  group('CheatSheetLog contract', () {
    late CheatSheetLog log;
    const a = BookId('a');
    const b = BookId('b');
    final t0 = DateTime.utc(2024);

    setUp(() async => log = await create());

    test('watch emits null while nothing was saved', () async {
      expect(await log.watch(a).first, isNull);
    });

    test('save then watch returns an equal snapshot', () async {
      final s = _snapshot('a', t0);
      await log.save(s);
      final back = await log.watch(a).first;
      expect(back, s);
      expect(back?.shownAt.isUtc, isTrue);
    });

    test('the order and the content of the words are kept', () async {
      final s = _snapshot(
        'a',
        t0,
        lemmas: const ['give up', 'zebra', 'apple', 'Ünï'],
      );
      await log.save(s);
      expect((await log.watch(a).first)?.lemmas, [
        'give up',
        'zebra',
        'apple',
        'Ünï',
      ]);
    });

    test('an empty list is a snapshot, not null', () async {
      final s = _snapshot('a', t0, lemmas: const []);
      await log.save(s);
      expect(await log.watch(a).first, s);
    });

    test('a new snapshot replaces the old one of the same book', () async {
      await log.save(_snapshot('a', t0));
      final newer = _snapshot(
        'a',
        t0.add(const Duration(hours: 1)),
        lemmas: const ['only'],
      );
      await log.save(newer);
      expect(await log.watch(a).first, newer);
    });

    test('books do not affect each other', () async {
      final sa = _snapshot('a', t0);
      final sb = _snapshot('b', t0, lemmas: const ['other']);
      await log.save(sa);
      await log.save(sb);
      expect(await log.watch(a).first, sa);
      expect(await log.watch(b).first, sb);
      await log.save(_snapshot('a', t0, lemmas: const []));
      expect(await log.watch(b).first, sb);
    });

    test('watch emits again after save, only for its own book', () async {
      final emitted = <CheatSheetSnapshot?>[];
      final sub = log.watch(a).listen(emitted.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(emitted, [null]);

      final s = _snapshot('a', t0);
      await log.save(s);
      await pumpEventQueue();
      expect(emitted, [null, s]);

      await log.save(_snapshot('b', t0));
      await pumpEventQueue();
      expect(emitted, [null, s]);
    });
  });
}
