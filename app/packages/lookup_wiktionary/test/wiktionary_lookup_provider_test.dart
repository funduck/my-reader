import 'dart:io';

import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:lookup_wiktionary/lookup_wiktionary.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// The mini pack built for T-030; shared with the service tests.
const String _miniPack =
    '../../../service/fixtures/packs/en-en-20260101.1.sqlite';

class _PathPackStore extends FakePackStore {
  new(this.path);

  final String? path;

  @override
  Future<String?> pathOf(String id) async => path;
}

LookupQuery _q(String text, {LookupMode mode = LookupMode.enEn}) =>
    LookupQuery(text: text, mode: mode);

WiktionaryLookupProvider _provider({LemmaCandidates? lemmas}) {
  final provider = WiktionaryLookupProvider(
    packStore: _PathPackStore(_miniPack),
    lemmas: lemmas,
  );
  addTearDown(provider.close);
  return provider;
}

void main() {
  lookupProviderContract(
    _provider,
    known: _q('go'),
    unknown: _q('zzzxqv'),
    createUnavailable: () =>
        WiktionaryLookupProvider(packStore: _PathPackStore(null)),
  );

  group('WiktionaryLookupProvider', () {
    test('maps senses, parts of speech, examples and IPA', () async {
      final result = await _provider().lookup(_q('go'));
      expect(result.provider, WiktionaryLookupProvider.providerId);
      expect(result.transcription, '/ɡoʊ/');
      final first = result.senses.first;
      expect(first.text, 'To move or travel from one place to another.');
      expect(first.partOfSpeech, 'verb');
      expect(first.examples, ['I go to work by bus.']);
      expect(result.senses.last.partOfSpeech, 'noun');
    });

    test('a sense without examples has an empty list', () async {
      final dir = Directory.systemTemp.createTempSync('wikt');
      addTearDown(() => dir.deleteSync(recursive: true));
      final copy = File('${dir.path}/en-en.sqlite');
      File(_miniPack).copySync(copy.path);
      sqlite3.open(copy.path)
        ..execute('DELETE FROM examples WHERE sense_id = 2')
        ..close();
      final provider = WiktionaryLookupProvider(
        packStore: _PathPackStore(copy.path),
      );
      addTearDown(provider.close);
      final result = await provider.lookup(_q('go'));
      final sense = result.senses.firstWhere(
        (s) => s.text == 'To leave a place.',
      );
      expect(sense.examples, isEmpty);
      expect(result.senses.first.examples, ['I go to work by bus.']);
    });

    test('normalizes case, apostrophes, whitespace', () async {
      final provider = _provider();
      expect((await provider.lookup(_q('  GO '))).senses, isNotEmpty);
      expect((await provider.lookup(_q('can’t'))).senses, isNotEmpty);
      expect((await provider.lookup(_q('take   off'))).senses, isNotEmpty);
    });

    test('merges entries sharing a key (Polish / polish)', () async {
      final result = await _provider().lookup(_q('Polish'));
      expect(
        result.senses.map((s) => s.partOfSpeech),
        containsAll(['adj', 'verb']),
      );
    });

    test('tries the lemma first, then the surface form', () async {
      final provider = _provider(lemmas: (t) => t == 'went' ? ['go'] : []);
      final viaLemma = await provider.lookup(_q('went'));
      expect(viaLemma.senses.first.partOfSpeech, 'verb');
      final direct = await provider.lookup(_q('serendipity'));
      expect(direct.senses, isNotEmpty);

      final fallback = _provider(lemmas: (t) => ['nonexistentlemma']);
      expect((await fallback.lookup(_q('cat'))).senses, isNotEmpty);
    });

    test('enRu is unavailable, not "not found"', () async {
      final provider = _provider();
      expect(provider.supports(LookupMode.enRu), isFalse);
      await expectLater(
        provider.lookup(_q('go', mode: LookupMode.enRu)),
        throwsA(isA<ProviderUnavailable>()),
      );
    });

    test('a missing pack file is ProviderUnavailable', () async {
      final provider = WiktionaryLookupProvider(
        packStore: _PathPackStore('/nonexistent/en-en.sqlite'),
      );
      await expectLater(
        provider.lookup(_q('go')),
        throwsA(isA<ProviderUnavailable>()),
      );
    });

    test('a not installed pack names the pack in the reason', () async {
      final provider = WiktionaryLookupProvider(
        packStore: _PathPackStore(null),
      );
      await expectLater(
        provider.lookup(_q('go')),
        throwsA(
          isA<ProviderUnavailable>().having(
            (e) => e.message,
            'message',
            contains('en-en'),
          ),
        ),
      );
    });
  });
}
