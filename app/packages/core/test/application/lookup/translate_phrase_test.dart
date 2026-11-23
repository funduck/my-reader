import 'dart:async';

import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:test/test.dart';

import 'fakes.dart';

class _Journal implements PhraseJournal {
  final List<PhraseLookup> items = [];

  @override
  Future<void> record(PhraseLookup phrase) async {
    if (items.any((p) => p.id == phrase.id)) return;
    items.add(phrase);
  }

  @override
  Stream<List<PhraseLookup>> watchAll() => const Stream.empty();

  @override
  Future<List<PhraseLookup>> byBook(BookId book) async => items;

  @override
  Future<void> delete(PhraseLookupId id) async {}
}

const _at = Locator(
  book: BookId('b1'),
  chapter: ChapterRef(href: 'c.xhtml', index: 0),
  progression: 0.1,
  quote: TextQuote(exact: 'gave up'),
);

class _Delayed implements LookupProvider {
  new(this._inner, this._delay);

  final LookupProvider _inner;
  final Duration _delay;

  @override
  ProviderId get id => _inner.id;

  @override
  ProviderInfo get info => _inner.info;

  @override
  bool supports(LookupMode mode) => _inner.supports(mode);

  @override
  Future<LookupResult> lookup(LookupQuery query, {CancelToken? cancel}) =>
      Future<void>.delayed(_delay).then((_) => _inner.lookup(query));
}

void main() {
  late _Journal journal;
  late ScriptedProvider provider;

  setUp(() {
    journal = _Journal();
    provider = ScriptedProvider(
      'deepl',
      modes: {LookupMode.enRu},
      answer: result('deepl', ['  сдался ']),
    );
  });

  TranslatePhrase scenario() => TranslatePhrase(
    provider: provider,
    journal: journal,
    clock: FixedClock(DateTime.utc(2026, 1, 2)),
    ids: CountingIds(),
  );

  test('success: translation from the provider, nothing written yet', () async {
    final outcome = await scenario()(
      text: ' he gave up ',
      sentence: 'Then he gave up.',
      locator: _at,
    );

    expect(outcome, isA<PhraseTranslated>());
    final translated = outcome as PhraseTranslated;
    expect(translated.text, 'he gave up');
    expect(translated.translation, 'сдался');
    expect(translated.provider.value, 'deepl');
    expect(provider.calls.single.mode, LookupMode.enRu);
    expect(provider.calls.single.sentence, 'Then he gave up.');
    expect(journal.items, isEmpty);
  });

  test('record writes the entry; a second record does not duplicate', () async {
    final s = scenario();
    final outcome = await s(
      text: 'he gave up',
      sentence: 'S',
      locator: _at,
    ) as PhraseTranslated;

    expect(await s.record(outcome), isTrue);
    expect(await s.record(outcome), isTrue);

    final entry = journal.items.single;
    expect(entry.id, outcome.id);
    expect(entry.text, 'he gave up');
    expect(entry.translation, 'сдался');
    expect(entry.sentence, 'S');
    expect(entry.locator, _at);
    expect(entry.at, DateTime.utc(2026, 1, 2));
  });

  test('without a locator nothing can be recorded', () async {
    final s = scenario();
    final outcome = await s(text: 'he gave up') as PhraseTranslated;

    expect(await s.record(outcome), isFalse);
    expect(journal.items, isEmpty);
  });

  test('another call is another entry', () async {
    final s = scenario();
    final a = await s(text: 'he gave up', locator: _at) as PhraseTranslated;
    final b = await s(text: 'he gave up', locator: _at) as PhraseTranslated;
    await s.record(a);
    await s.record(b);

    expect(journal.items, hasLength(2));
  });

  group('failures are values and write nothing', () {
    const cases = {
      'no_key': PhraseFailureKind.noKey,
      'network': PhraseFailureKind.network,
      'timeout': PhraseFailureKind.timeout,
      'bad_key: HTTP 403': PhraseFailureKind.badKey,
      'quota': PhraseFailureKind.quota,
      'rate_limit': PhraseFailureKind.rateLimit,
      'server_error': PhraseFailureKind.serverError,
      'http_418': PhraseFailureKind.other,
      'bad_response': PhraseFailureKind.other,
    };
    for (final MapEntry(key: message, value: kind) in cases.entries) {
      test(message, () async {
        provider.failure = ProviderUnavailable(message);
        final outcome = await scenario()(text: 'a b', locator: _at);

        expect(outcome, PhraseFailed(kind: kind, message: message));
        expect(journal.items, isEmpty);
      });
    }

    test('LookupNotFound and an empty translation', () async {
      provider.failure = const LookupNotFound();
      expect(
        await scenario()(text: 'a b', locator: _at),
        const PhraseFailed(kind: PhraseFailureKind.notFound),
      );
      provider
        ..failure = null
        ..answer = result('deepl', ['  ']);
      expect(
        await scenario()(text: 'a b', locator: _at),
        const PhraseFailed(kind: PhraseFailureKind.notFound),
      );
      expect(journal.items, isEmpty);
    });
  });

  test('a cancelled token throws and the provider is not asked', () async {
    final cancel = CancelToken()..cancel();

    await expectLater(
      scenario()(text: 'a b', cancel: cancel),
      throwsA(isA<CancelledException>()),
    );
    expect(provider.calls, isEmpty);
  });

  test(
    'is not limited by a chain timeout: waits for a slow provider',
    () async {
      final s = TranslatePhrase(
        provider: _Delayed(provider, const Duration(milliseconds: 80)),
        journal: journal,
        clock: FixedClock(DateTime.utc(2026)),
        ids: CountingIds(),
      );
      expect(await s(text: 'a b'), isA<PhraseTranslated>());
    },
  );
}
