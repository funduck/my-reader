import 'dart:async';
import 'dart:convert';

import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lookup_sheet/lookup_sheet.dart';
import 'package:my_reader_app/bootstrap.dart';
import 'package:reader_api/reader_api.dart';

import 'support/lookup_e2e.dart';

class _FakeEngine implements ReaderEngine {
  final _events = StreamController<ReaderEvent>.broadcast();

  void emit(ReaderEvent event) => _events.add(event);

  @override
  Widget buildView(BuildContext context) => const Text(fixtureParagraph);

  @override
  Future<void> load(
    OpenedBook book, {
    required BookId bookId,
    Locator? at,
  }) async {}

  @override
  Future<void> goTo(Locator locator) async {}

  @override
  void applySettings(ReaderSettings settings) {}

  @override
  void highlight(ReaderHighlights highlights) {}

  @override
  Stream<ReaderEvent> get events => _events.stream;

  @override
  Future<void> dispose() => _events.close();
}

/// Phrase scenario of T-094: selection in the reader -> sheet -> DeepL over a
/// fake HTTP client -> the phrase journal. Never calls the real DeepL.
void main() {
  const phrase = 'come here';
  const translation = 'иди сюда';

  testWidgets('phrase selected in the reader: translated by DeepL and '
      'recorded in the phrase journal, not in the word history', (
    tester,
  ) async {
    final fixture = await LookupFixture.create();
    final engine = _FakeEngine();
    final requests = <http.Request>[];
    final deepl = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode({
          'translations': [
            {'text': translation},
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    const at = Locator(
      book: fixtureBookId,
      chapter: ChapterRef(href: 'chapter1.xhtml', index: 0),
      progression: 0.5,
      quote: TextQuote(exact: phrase),
    );
    await tester.pumpWidget(
      bootstrap(
        overrides: [
          ...fixture.overrides(engine: () => engine),
          secretStoreProvider.overrideWithValue(
            FakeSecretStore({deeplApiKey: 'test-key:fx'}),
          ),
          phraseJournalProvider.overrideWithValue(
            fixture.database.phraseJournal,
          ),
          httpClientProvider.overrideWithValue(deepl),
        ],
      ),
    );

    // Drift and sqlite finish outside the fake-async zone.
    Future<void> settle([bool Function()? done]) async {
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (done != null && done()) return;
      }
      if (done != null) fail('the condition did not come true');
    }

    bool shown() => find.text(translation).evaluate().isNotEmpty;

    await settle(() => find.byType(Text).evaluate().isNotEmpty);
    engine.emit(
      const TextSelected(text: phrase, at: at, sentence: fixtureParagraph),
    );
    await settle(shown);

    expect(find.byKey(const Key('lookup-mode-toggle')), findsNothing);
    expect(
      await tester.runAsync(
        () => fixture.database.phraseJournal.watchAll().first,
      ),
      isEmpty,
      reason: 'not recorded before 2 s on screen',
    );

    await tester.pump(minLookupViewDuration);
    await settle();

    final entries = (await tester.runAsync(
      () => fixture.database.phraseJournal.watchAll().first,
    ))!;
    expect(entries, hasLength(1));
    expect(entries.single.text, phrase);
    expect(entries.single.translation, translation);
    expect(entries.single.provider.value, 'deepl');
    expect(entries.single.sentence, fixtureParagraph);
    expect(entries.single.locator.book, fixtureBookId);

    // Words and terms are untouched; nothing went to the pack service.
    expect(await tester.runAsync(() => journalOf(fixture)), isEmpty);
    expect(await tester.runAsync(() => termsOf(fixture)), isEmpty);
    expect(fixture.client.attempts, isEmpty);

    // One request to DeepL Free, with the key and the context sentence.
    final request = requests.single;
    expect(request.url.host, 'api-free.deepl.com');
    expect(request.headers['Authorization'], 'DeepL-Auth-Key test-key:fx');
    final body = jsonDecode(request.body) as Map<String, Object?>;
    expect(body['text'], [phrase]);
    expect(body['context'], fixtureParagraph);

    await unmountApp(tester);
  });
}
