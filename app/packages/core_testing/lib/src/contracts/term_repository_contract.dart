import 'dart:async';

import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:test/test.dart';

Term _term(
  String id,
  String word, {
  String language = 'en',
  int count = 1,
  TermStatus status = TermStatus.learning,
}) => Term(
  id: TermId(id),
  normalized: word,
  language: language,
  lookupCount: count,
  eventIds: [LookupEventId('e-$id')],
  status: status,
);

/// Behaviour every [TermRepository] must have.
///
/// [create] returns a fresh, empty repository for each test.
void termRepositoryContract(FutureOr<TermRepository> Function() create) {
  group('TermRepository contract', () {
    late TermRepository repo;

    setUp(() async => repo = await create());

    test('find returns null for an unknown term', () async {
      expect(await repo.find('word', 'en'), isNull);
    });

    test('save then find returns an equal term', () async {
      final term = _term('t1', 'word', count: 3);
      await repo.save(term);
      expect(await repo.find('word', 'en'), term);
    });

    test('find distinguishes language and normalized text', () async {
      await repo.save(_term('t1', 'word'));
      expect(await repo.find('word', 'de'), isNull);
      expect(await repo.find('words', 'en'), isNull);
    });

    test('save with an existing id replaces the term', () async {
      await repo.save(_term('t1', 'word'));
      final updated = _term('t1', 'word', count: 2, status: TermStatus.known);
      await repo.save(updated);
      expect(await repo.find('word', 'en'), updated);
      expect(await repo.watchAll().first, [updated]);
    });

    test(
      'watchAll emits all terms first, filtered by status if given',
      () async {
        final learning = _term('t1', 'one');
        final known = _term('t2', 'two', status: TermStatus.known);
        await repo.save(learning);
        await repo.save(known);

        final all = await repo.watchAll().first;
        expect(all, unorderedEquals([learning, known]));
        expect(await repo.watchAll(status: TermStatus.known).first, [known]);
        expect(await repo.watchAll(status: TermStatus.ignored).first, isEmpty);
      },
    );

    test('watchAll emits again after save', () async {
      final emitted = <List<Term>>[];
      final sub = repo.watchAll().listen(emitted.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(emitted, [<Term>[]]);

      final term = _term('t1', 'word');
      await repo.save(term);
      await pumpEventQueue();
      expect(emitted.last, [term]);
    });
  });
}
