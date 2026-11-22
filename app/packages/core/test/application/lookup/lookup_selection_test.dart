import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  late MemoryProfiles profiles;
  late MemoryJournal journal;
  late MemoryTerms terms;
  late FixedClock clock;
  late MapLevels levels;

  setUp(() {
    profiles = MemoryProfiles();
    journal = MemoryJournal();
    terms = MemoryTerms();
    clock = FixedClock(DateTime.utc(2024, 5, 1, 12));
    levels = MapLevels({'run': CefrLevel.a2});
  });

  LookupSelection selection(
    List<LookupProvider> providers, {
    Duration timeout = const Duration(milliseconds: 20),
  }) => LookupSelection(
    chain: ProviderChain(
      providers: providers,
      profiles: profiles,
      timeout: timeout,
    ),
    analyzer: SimpleAnalyzer(),
    levels: levels,
    journal: journal,
    terms: terms,
    profiles: profiles,
    clock: clock,
    ids: CountingIds(),
  );

  const locator = Locator(
    book: BookId('b1'),
    chapter: ChapterRef(href: 'c1.xhtml', index: 0),
    progression: 0.5,
  );

  group('answered', () {
    test('records an event with query, result and time', () async {
      final a = ScriptedProvider('a', answer: result('a'));
      final out = await selection([a])(
        text: '  Running ',
        sentence: 'He is Running.',
        locator: locator,
      );
      final answered = out as LookupAnswered;
      expect(answered.result, result('a'));
      expect(journal.events, [answered.event]);
      final query = answered.event.query;
      expect(query.text, 'Running');
      expect(query.mode, LookupMode.enEn);
      expect(query.sentence, 'He is Running.');
      expect(query.locator, locator);
      expect(answered.event.at, DateTime.utc(2024, 5, 1, 12));
      expect(a.calls.single, query);
    });

    test('mode defaults to the profile, explicit mode wins', () async {
      profiles.profile = const UserProfile(mode: LookupMode.enRu);
      final a = ScriptedProvider('a', answer: result('a'));
      final s = selection([a]);
      await s(text: 'run');
      await s(text: 'run', mode: LookupMode.enEn);
      expect(a.calls.map((q) => q.mode), [LookupMode.enRu, LookupMode.enEn]);
    });

    test('creates a term keyed by lemma with the level', () async {
      final a = ScriptedProvider('a', answer: result('a'));
      final out = await selection([a])(text: 'Runs');
      final term = terms.terms.values.single;
      expect(term.normalized, 'run');
      expect(term.language, 'en');
      expect(term.lookupCount, 1);
      expect(term.eventIds, [out.event.id]);
      expect(term.level, CefrLevel.a2);
      expect(term.status, TermStatus.learning);
      expect(out.term, term);
      expect(out.level, CefrLevel.a2);
      expect(out.wordLevel, const WordLevel(CefrLevel.a2));
    });

    test('the level is asked by the lemma, not the surface form', () async {
      final a = ScriptedProvider('a', answer: result('a'));
      await selection([a])(text: '  Runs ');
      expect(levels.asked, ['run']);
    });

    test('an estimated level is flagged in the outcome', () async {
      levels = MapLevels({'run': CefrLevel.b2}, {'run'});
      final a = ScriptedProvider('a', answer: result('a'));
      final out = await selection([a])(text: 'run');
      expect(out.wordLevel, const WordLevel(CefrLevel.b2, estimated: true));
      expect(out.level, CefrLevel.b2);
    });

    test('an unknown word gives an unknown level', () async {
      final a = ScriptedProvider('a', answer: result('a'));
      final out = await selection([a])(text: 'Give up');
      expect(out.level, CefrLevel.unknown);
      expect(levels.asked, ['give up']);
    });

    test('the level is returned also when no provider answered', () async {
      final a = ScriptedProvider('a', failure: const LookupNotFound());
      final out = await selection([a])(text: 'run') as LookupUnanswered;
      expect(out.wordLevel, const WordLevel(CefrLevel.a2));
    });

    test('repeat lookup updates the same term, keeps status', () async {
      final a = ScriptedProvider('a', answer: result('a'));
      final s = selection([a]);
      final first = await s(text: 'run');
      final id = terms.terms.values.single.id;
      terms.terms[id] = terms.terms[id]!.copyWith(status: TermStatus.known);
      clock.time = clock.time.add(const Duration(minutes: 1));
      final second = await s(text: 'runs');
      final term = terms.terms.values.single;
      expect(terms.terms, hasLength(1));
      expect(term.id, id);
      expect(term.lookupCount, 2);
      expect(term.eventIds, [first.event.id, second.event.id]);
      expect(term.status, TermStatus.known);
      expect(journal.events, hasLength(2));
    });

    test('a phrase is keyed by its lower-cased, collapsed text', () async {
      final a = ScriptedProvider('a', answer: result('a'));
      await selection([a])(text: 'Give   UP');
      expect(terms.terms.values.single.normalized, 'give up');
      expect(terms.terms.values.single.level, CefrLevel.unknown);
    });

    test('skipped providers are reported', () async {
      final a = ScriptedProvider('a', failure: const ProviderUnavailable());
      final b = ScriptedProvider('b', answer: result('b'));
      final out = await selection([a, b])(text: 'run') as LookupAnswered;
      expect(out.result.provider, const ProviderId('b'));
      expect(out.skipped.single.provider, const ProviderId('a'));
    });
  });

  group('explicit provider', () {
    test('asks only that provider and makes its own event', () async {
      final a = ScriptedProvider('a', answer: result('a'));
      final b = ScriptedProvider('b', answer: result('b'));
      final s = selection([a, b]);
      await s(text: 'run');
      final out = await s(text: 'run', provider: const ProviderId('b'));
      expect((out as LookupAnswered).result.provider, const ProviderId('b'));
      expect(a.calls, hasLength(1));
      expect(b.calls, hasLength(1));
      expect(journal.events, hasLength(2));
      expect(terms.terms.values.single.lookupCount, 2);
    });
  });

  group('all providers fail', () {
    test('event is recorded with an empty result', () async {
      final a = ScriptedProvider('a', failure: const ProviderUnavailable());
      final b = ScriptedProvider('b', hang: true);
      final out = await selection([a, b])(text: 'run', locator: locator);
      final failed = out as LookupUnanswered;
      expect(failed.isNotFound, isFalse);
      expect(journal.events, [failed.event]);
      expect(failed.event.result.senses, isEmpty);
      // Result names the last provider tried.
      expect(failed.event.result.provider, const ProviderId('b'));
      expect(failed.event.query.locator, locator);
      expect(failed.failure.attempts.map((x) => x.failure), [
        AttemptFailure.unavailable,
        AttemptFailure.timedOut,
      ]);
    });

    test('term is upserted too, so it matches the journal', () async {
      final a = ScriptedProvider('a', failure: const LookupNotFound());
      final s = selection([a]);
      final first = await s(text: 'run');
      final second = await s(text: 'run');
      final term = terms.terms.values.single;
      expect(term.lookupCount, 2);
      expect(term.eventIds, [first.event.id, second.event.id]);
      expect(term.level, CefrLevel.a2);
      expect((first as LookupUnanswered).isNotFound, isTrue);
    });

    test('no provider supports the mode: event names "none"', () async {
      final a = ScriptedProvider('a', modes: {LookupMode.enRu});
      final out = await selection([a])(text: 'run') as LookupUnanswered;
      expect(out.event.result.provider, noProvider);
      expect(out.failure.attempts, isEmpty);
      expect(journal.events, hasLength(1));
    });

    test('explicit provider fails: event is recorded', () async {
      final a = ScriptedProvider('a', answer: result('a'));
      final b = ScriptedProvider('b', failure: const ProviderUnavailable());
      final out = await selection([a, b])(
        text: 'run',
        provider: const ProviderId('b'),
      ) as LookupUnanswered;
      expect(out.event.result.provider, const ProviderId('b'));
      expect(a.calls, isEmpty);
      expect(journal.events, hasLength(1));
    });
  });

  group('cancellation', () {
    test('cancelled before start: nothing is written', () async {
      final a = ScriptedProvider('a', answer: result('a'));
      final token = CancelToken()..cancel();
      await expectLater(
        selection([a])(text: 'run', cancel: token),
        throwsA(isA<CancelledException>()),
      );
      expect(a.calls, isEmpty);
      expect(journal.events, isEmpty);
      expect(terms.terms, isEmpty);
    });

    test('cancelled during the lookup: nothing is written', () async {
      final token = CancelToken();
      final a = ScriptedProvider('a', onCall: token.cancel);
      final b = ScriptedProvider('b', answer: result('b'));
      await expectLater(
        selection([a, b])(text: 'run', cancel: token),
        throwsA(isA<CancelledException>()),
      );
      expect(b.calls, isEmpty);
      expect(journal.events, isEmpty);
      expect(terms.terms, isEmpty);
    });
  });
}
