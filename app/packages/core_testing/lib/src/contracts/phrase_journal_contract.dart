import 'dart:async';

import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:test/test.dart';

PhraseLookup _phrase(
  String id,
  DateTime at, {
  String text = 'gave up',
  String translation = 'сдался',
  String book = 'b1',
  String? sentence = 'He gave up.',
}) => PhraseLookup(
  id: PhraseLookupId(id),
  text: text,
  translation: translation,
  provider: const ProviderId('deepl'),
  at: at,
  locator: Locator(
    book: BookId(book),
    chapter: const ChapterRef(href: 'c1.xhtml', index: 0),
    progression: 0.25,
  ),
  sentence: sentence,
);

/// Behaviour every [PhraseJournal] must have.
///
/// [create] returns a fresh, empty journal for each test.
void phraseJournalContract(FutureOr<PhraseJournal> Function() create) {
  group('PhraseJournal contract', () {
    late PhraseJournal journal;
    final t0 = DateTime.utc(2024);
    DateTime at(int hours) => t0.add(Duration(hours: hours));

    setUp(() async => journal = await create());

    test('an empty journal emits an empty list', () async {
      expect(await journal.watchAll().first, isEmpty);
    });

    test('record then watchAll returns an equal entry', () async {
      final p = _phrase('p1', at(0));
      await journal.record(p);
      expect(await journal.watchAll().first, [p]);
    });

    test('an entry without a sentence round-trips', () async {
      final p = _phrase('p1', at(0), sentence: null);
      await journal.record(p);
      expect((await journal.watchAll().first).single.sentence, isNull);
    });

    test('watchAll is newest first', () async {
      final p1 = _phrase('p1', at(1));
      final p2 = _phrase('p2', at(3));
      final p3 = _phrase('p3', at(2));
      await journal.record(p1);
      await journal.record(p2);
      await journal.record(p3);
      expect(await journal.watchAll().first, [p2, p3, p1]);
    });

    test('watchAll emits again after record and delete', () async {
      final emitted = <List<PhraseLookup>>[];
      final sub = journal.watchAll().listen(emitted.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(emitted, [<PhraseLookup>[]]);

      final p = _phrase('p1', at(0));
      await journal.record(p);
      await pumpEventQueue();
      expect(emitted.last, [p]);

      await journal.delete(p.id);
      await pumpEventQueue();
      expect(emitted.last, isEmpty);
    });

    test('recording the same id again changes nothing', () async {
      final p = _phrase('p1', at(0));
      await journal.record(p);
      await journal.record(_phrase('p1', at(5), translation: 'другое'));
      expect(await journal.watchAll().first, [p]);
    });

    test('entries with the same text but different ids both stay', () async {
      await journal.record(_phrase('p1', at(0)));
      await journal.record(_phrase('p2', at(1)));
      expect(await journal.watchAll().first, hasLength(2));
    });

    test('byBook returns only that book, newest first', () async {
      final a1 = _phrase('p1', at(0));
      final a2 = _phrase('p2', at(2));
      await journal.record(a1);
      await journal.record(_phrase('p3', at(1), book: 'b2'));
      await journal.record(a2);
      expect(await journal.byBook(const BookId('b1')), [a2, a1]);
      expect(await journal.byBook(const BookId('none')), isEmpty);
    });

    test('delete removes the entry; an unknown id does nothing', () async {
      final p1 = _phrase('p1', at(0));
      final p2 = _phrase('p2', at(1));
      await journal.record(p1);
      await journal.record(p2);
      await journal.delete(p1.id);
      await journal.delete(const PhraseLookupId('nope'));
      expect(await journal.watchAll().first, [p2]);
    });
  });
}
