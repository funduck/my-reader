import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:storage_drift/storage_drift.dart';
import 'package:test/test.dart';

AppDatabase _inMemory() {
  final db = openInMemory();
  addTearDown(db.close);
  return db;
}

LookupEvent _event(
  String id,
  DateTime at, {
  String text = 'ran',
  Locator? locator,
  String? sentence,
}) => LookupEvent(
  id: LookupEventId(id),
  query: LookupQuery(
    text: text,
    mode: LookupMode.enRu,
    sentence: sentence,
    locator: locator,
  ),
  result: const LookupResult(
    provider: ProviderId('stardict.test'),
    transcription: '/ræn/',
    senses: [
      Sense(
        text: 'бежал',
        partOfSpeech: 'verb',
        examples: ['He ran home.', 'She ran.'],
      ),
      Sense(text: 'управлял'),
    ],
  ),
  at: at,
);

void main() {
  final t0 = DateTime.utc(2024, 3);

  group('LookupJournal (drift)', () {
    test('an event with locator, sentence and senses round-trips', () async {
      final journal = _inMemory().lookupJournal;
      final locator = Locator(
        book: const BookId('b1'),
        chapter: const ChapterRef(href: 'OEBPS/c1.xhtml#a', index: 2),
        progression: 0.25,
        quote: TextQuote.fromText('He ran home quickly.', 3, 6),
        engineHint: 'offset:7',
      );
      final event = _event(
        'e1',
        DateTime.utc(2024, 3, 1, 1, 2, 3, 4, 5),
        locator: locator,
        sentence: 'He ran home quickly.',
      );
      await journal.record(event);

      final loaded = await journal.get(event.id);
      expect(loaded, event);
      expect(loaded!.query.locator!.quote, locator.quote);
      expect(loaded.query.locator!.engineHint, 'offset:7');
      expect(loaded.at, event.at);
    });

    test('recording the same id twice fails and keeps the first', () async {
      final journal = _inMemory().lookupJournal;
      final first = _event('e1', t0);
      await journal.record(first);
      await expectLater(
        journal.record(_event('e1', t0, text: 'other')),
        throwsA(anything),
      );
      expect(await journal.get(first.id), first);
    });

    test('equal times: the later record comes first', () async {
      final journal = _inMemory().lookupJournal;
      final a = _event('a', t0);
      final b = _event('b', t0);
      await journal.record(a);
      await journal.record(b);
      expect(await journal.watch().first, [b, a]);
    });

    test('chapter filter needs both href and index to match', () async {
      final journal = _inMemory().lookupJournal;
      Locator at(String href, int index) => Locator(
        book: const BookId('b1'),
        chapter: ChapterRef(href: href, index: index),
        progression: 0,
      );
      final match = _event('e1', t0, locator: at('c1.xhtml', 1));
      await journal.record(match);
      await journal.record(_event('e2', t0, locator: at('c1.xhtml', 2)));
      await journal.record(_event('e3', t0, locator: at('c2.xhtml', 1)));
      final got = await journal
          .watch(
            const LookupFilter(
              book: BookId('b1'),
              chapter: ChapterRef(href: 'c1.xhtml', index: 1),
            ),
          )
          .first;
      expect(got, [match]);
    });

    test('level filter follows the level of the linked term', () async {
      final db = _inMemory();
      final journal = db.lookupJournal;
      final terms = db.termRepository;
      final hard = _event('e1', t0);
      final easy = _event('e2', t0.add(const Duration(hours: 1)));
      final orphan = _event('e3', t0.add(const Duration(hours: 2)));
      for (final e in [hard, easy, orphan]) {
        await journal.record(e);
      }
      await terms.upsert(
        id: const TermId('t1'),
        lemma: 'run',
        language: 'en',
        event: hard.id,
        level: CefrLevel.c1,
      );
      await terms.upsert(
        id: const TermId('t2'),
        lemma: 'go',
        language: 'en',
        event: easy.id,
        level: CefrLevel.a1,
      );

      expect(
        await journal.watch(const LookupFilter(level: CefrLevel.c1)).first,
        [hard],
      );
      expect(
        await journal.watch(const LookupFilter(level: CefrLevel.a1)).first,
        [easy],
      );
      expect(
        await journal.watch(const LookupFilter(level: CefrLevel.b2)).first,
        <LookupEvent>[],
      );
    });

    test('a level-filtered stream re-emits when a term changes', () async {
      final db = _inMemory();
      final journal = db.lookupJournal;
      final e = _event('e1', t0);
      await journal.record(e);
      final emitted = <List<LookupEvent>>[];
      final sub = journal
          .watch(const LookupFilter(level: CefrLevel.b1))
          .listen(emitted.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(emitted.last, isEmpty);

      await db.termRepository.upsert(
        id: const TermId('t1'),
        lemma: 'run',
        language: 'en',
        event: e.id,
        level: CefrLevel.b1,
      );
      await pumpEventQueue();
      expect(emitted.last, [e]);
    });

    test('byTerm lists the events of that term, newest first', () async {
      final db = _inMemory();
      final e1 = _event('e1', t0);
      final e2 = _event('e2', t0.add(const Duration(hours: 1)), text: 'run');
      final other = _event('e3', t0.add(const Duration(hours: 2)), text: 'go');
      for (final e in [e1, e2, other]) {
        await db.lookupJournal.record(e);
      }
      await db.termRepository.upsert(
        id: const TermId('t1'),
        lemma: 'run',
        language: 'en',
        event: e1.id,
      );
      await db.termRepository.upsert(
        id: const TermId('t9'),
        lemma: 'run',
        language: 'en',
        event: e2.id,
      );
      await db.termRepository.upsert(
        id: const TermId('t2'),
        lemma: 'go',
        language: 'en',
        event: other.id,
      );

      expect(await db.lookupJournal.byTerm(const TermId('t1')), [e2, e1]);
      expect(await db.lookupJournal.byTerm(const TermId('t2')), [other]);
      expect(await db.lookupJournal.byTerm(const TermId('none')), isEmpty);
    });
  });

  group('TermRepository (drift)', () {
    test('two lookups of one lemma make one Term with count 2', () async {
      final db = _inMemory();
      final terms = db.termRepository;
      final e1 = _event('e1', t0);
      final e2 = _event('e2', t0.add(const Duration(minutes: 1)), text: 'run');
      await db.lookupJournal.record(e1);
      await db.lookupJournal.record(e2);

      final first = await terms.upsert(
        id: const TermId('t1'),
        lemma: 'run',
        language: 'en',
        event: e1.id,
      );
      final second = await terms.upsert(
        id: const TermId('t2'),
        lemma: 'run',
        language: 'en',
        event: e2.id,
      );

      expect(first.lookupCount, 1);
      expect(second.id, const TermId('t1'));
      expect(second.lookupCount, 2);
      expect(second.eventIds, [e1.id, e2.id]);
      final all = await terms.watchAll().first;
      expect(all, hasLength(1));
      expect(all.single, second);
      expect(await terms.byLemma('run'), second);
    });

    test('upsert keeps a known level when the new one is unknown', () async {
      final terms = _inMemory().termRepository;
      await terms.upsert(
        id: const TermId('t1'),
        lemma: 'run',
        language: 'en',
        event: const LookupEventId('e1'),
        level: CefrLevel.a2,
      );
      final again = await terms.upsert(
        id: const TermId('t2'),
        lemma: 'run',
        language: 'en',
        event: const LookupEventId('e2'),
      );
      expect(again.level, CefrLevel.a2);
      expect(again.lookupCount, 2);
    });

    test('byLemma separates languages and returns null for unknown', () async {
      final terms = _inMemory().termRepository;
      await terms.upsert(
        id: const TermId('t1'),
        lemma: 'run',
        language: 'en',
        event: const LookupEventId('e1'),
      );
      expect(await terms.byLemma('run', language: 'de'), isNull);
      expect(await terms.byLemma('walk'), isNull);
    });

    test('eventIds keep their order after save', () async {
      final terms = _inMemory().termRepository;
      const ids = [LookupEventId('z'), LookupEventId('a'), LookupEventId('m')];
      await terms.save(
        const Term(
          id: TermId('t1'),
          normalized: 'run',
          language: 'en',
          lookupCount: 3,
          eventIds: ids,
        ),
      );
      expect((await terms.find('run', 'en'))!.eventIds, ids);
    });

    test('allLemmas returns lemmas by language and status', () async {
      final terms = _inMemory().termRepository;
      Term term(String id, String lemma, String lang, TermStatus status) =>
          Term(
            id: TermId(id),
            normalized: lemma,
            language: lang,
            lookupCount: 1,
            eventIds: const [],
            status: status,
          );
      await terms.save(term('1', 'run', 'en', TermStatus.learning));
      await terms.save(term('2', 'go', 'en', TermStatus.known));
      await terms.save(term('3', 'laufen', 'de', TermStatus.learning));

      expect(await terms.allLemmas(), {'run', 'go'});
      expect(await terms.allLemmas(status: TermStatus.known), {'go'});
      expect(await terms.allLemmas(language: 'de'), {'laufen'});
      expect(await _inMemory().termRepository.allLemmas(), isEmpty);
    });

    test('watchAll(status) re-emits after upsert', () async {
      final terms = _inMemory().termRepository;
      final emitted = <List<Term>>[];
      final sub = terms.watchAll().listen(emitted.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(emitted.last, isEmpty);
      await terms.upsert(
        id: const TermId('t1'),
        lemma: 'run',
        language: 'en',
        event: const LookupEventId('e1'),
      );
      await pumpEventQueue();
      expect(emitted.last.single.lookupCount, 1);
    });
  });
}
