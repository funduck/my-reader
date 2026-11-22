import 'dart:async';

import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:test/test.dart';

const _provider = ProviderId('p');

LookupEvent _event(
  String id,
  DateTime at, {
  String book = 'b1',
  int chapter = 0,
  bool withLocator = true,
}) => LookupEvent(
  id: LookupEventId(id),
  query: LookupQuery(
    text: 'word',
    mode: LookupMode.enEn,
    locator: withLocator
        ? Locator(
            book: BookId(book),
            chapter: ChapterRef(href: 'c$chapter.xhtml', index: chapter),
            progression: 0.5,
          )
        : null,
  ),
  result: const LookupResult(
    provider: _provider,
    senses: [Sense(text: 'a word')],
  ),
  at: at,
);

/// Behaviour every [LookupJournal] must have.
///
/// [create] returns a fresh, empty journal for each test. The filter by
/// `level` is not covered: an event does not carry its term's level, so how
/// it is resolved depends on the implementation.
void lookupJournalContract(FutureOr<LookupJournal> Function() create) {
  group('LookupJournal contract', () {
    late LookupJournal journal;
    final t0 = DateTime.utc(2024);
    DateTime at(int hours) => t0.add(Duration(hours: hours));

    setUp(() async => journal = await create());

    test('get returns null for an unknown id', () async {
      expect(await journal.get(const LookupEventId('nope')), isNull);
    });

    test('record then get returns an equal event', () async {
      final e = _event('e1', at(0));
      await journal.record(e);
      expect(await journal.get(e.id), e);
    });

    test('watch emits the current events first, newest first', () async {
      final e1 = _event('e1', at(1));
      final e2 = _event('e2', at(3));
      final e3 = _event('e3', at(2));
      await journal.record(e1);
      await journal.record(e2);
      await journal.record(e3);
      expect(await journal.watch().first, [e2, e3, e1]);
    });

    test('watch emits again after record', () async {
      final emitted = <List<LookupEvent>>[];
      final sub = journal.watch().listen(emitted.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(emitted, [<LookupEvent>[]]);

      final e = _event('e1', at(0));
      await journal.record(e);
      await pumpEventQueue();
      expect(emitted.last, [e]);
    });

    test('filter by book', () async {
      final mine = _event('e1', at(0));
      await journal.record(mine);
      await journal.record(_event('e2', at(1), book: 'b2'));
      await journal.record(_event('e3', at(2), withLocator: false));
      final got = await journal
          .watch(LookupFilter(book: mine.query.locator!.book))
          .first;
      expect(got, [mine]);
    });

    test('filter by chapter', () async {
      final first = _event('e1', at(0));
      final second = _event('e2', at(1), chapter: 1);
      await journal.record(first);
      await journal.record(second);
      final filter = LookupFilter(
        book: second.query.locator!.book,
        chapter: second.query.locator!.chapter,
      );
      expect(await journal.watch(filter).first, [second]);
    });

    test('filter by time: from is inclusive, to is exclusive', () async {
      final e0 = _event('e0', at(0));
      final e1 = _event('e1', at(1));
      final e2 = _event('e2', at(2));
      for (final e in [e0, e1, e2]) {
        await journal.record(e);
      }
      expect(await journal.watch(LookupFilter(from: at(1))).first, [e2, e1]);
      expect(await journal.watch(LookupFilter(to: at(2))).first, [e1, e0]);
      expect(await journal.watch(LookupFilter(from: at(1), to: at(2))).first, [
        e1,
      ]);
    });

    test('an empty filter returns everything', () async {
      await journal.record(_event('e1', at(0)));
      await journal.record(_event('e2', at(1), withLocator: false));
      expect(await journal.watch().first, hasLength(2));
    });
  });
}
