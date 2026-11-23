import 'dart:async';

import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup_sheet/lookup_sheet.dart';
import 'package:material_ui/material_ui.dart';

import 'term_support.dart';

const _deepl = ProviderId('deepl');
const _dict = ProviderId('dict');
const _place = Locator(
  book: BookId('b1'),
  chapter: ChapterRef(href: 'c.xhtml', index: 0),
  progression: 0.2,
  quote: TextQuote(exact: 'gave up'),
);
const _phrase = 'He gave up';
const _phraseQuery = LookupQuery(
  text: _phrase,
  mode: LookupMode.enEn,
  sentence: 'Then he gave up.',
  locator: _place,
);
const _wordQuery = LookupQuery(text: 'cat', mode: LookupMode.enEn);

/// The dictionary side: answers every word, counts calls, records nothing.
class _Selection implements LookupSelection {
  final calls = <String>[];

  @override
  Future<LookupOutcome> call({
    required String text,
    LookupMode? mode,
    String? sentence,
    Locator? locator,
    ProviderId? provider,
    CancelToken? cancel,
  }) async {
    calls.add(text);
    return LookupAnswered(
      event: LookupEvent(
        id: LookupEventId('e${calls.length}'),
        query: _wordQuery,
        result: const LookupResult(
          provider: _dict,
          senses: [Sense(text: 'a pet')],
        ),
        at: DateTime.utc(2026),
      ),
      wordLevel: const WordLevel(CefrLevel.a1),
      skipped: const [],
    );
  }

  @override
  Future<Term> record(LookupOutcome outcome) async =>
      throw UnimplementedError();
}

/// Ends a sentence at `.` followed by a space.
class _TwoSentences extends WordAnalyzer {
  @override
  List<SentenceSpan> sentences(String text) {
    final cut = text.indexOf('. ');
    if (cut < 0) return [SentenceSpan(0, text.length)];
    return [SentenceSpan(0, cut + 1), SentenceSpan(cut + 2, text.length)];
  }
}

class _Fixture {
  new() {
    deepl = FakeLookupProvider(
      id: _deepl,
      info: const ProviderInfo(
        name: 'DeepL',
        isOnline: true,
        modes: {LookupMode.enRu},
      ),
      answers: const {
        'he gave up': LookupResult(
          provider: _deepl,
          senses: [Sense(text: 'Он сдался')],
        ),
      },
    );
  }

  late final FakeLookupProvider deepl;
  final journal = FakePhraseJournal();
  final selection = _Selection();
  int settingsOpened = 0;

  Future<int> count() async =>
      (await journal.byBook(const BookId('b1'))).length;

  Future<void> open(WidgetTester tester, LookupQuery query) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          phraseProviderProvider.overrideWithValue(deepl),
          phraseJournalProvider.overrideWithValue(journal),
          clockProvider.overrideWithValue(FakeClock(DateTime.utc(2026, 3))),
          idGeneratorProvider.overrideWithValue(SeqIdGenerator()),
          lookupSelectionProvider.overrideWithValue(selection),
          ...TermSupport().overrides(ids: false, analyzer: _TwoSentences()),
          lookupProvidersProvider.overrideWithValue([
            FakeLookupProvider(
              id: _dict,
              info: const ProviderInfo(
                name: 'Dict',
                isOnline: false,
                modes: {LookupMode.enEn, LookupMode.enRu},
              ),
            ),
          ]),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => unawaited(
                  showLookupSheet(
                    context,
                    query,
                    onOpenSettings: () => settingsOpened++,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  testWidgets('one word goes to the dictionary, not to DeepL', (tester) async {
    final f = _Fixture();
    await f.open(tester, _wordQuery);

    expect(f.selection.calls, isNotEmpty);
    expect(f.deepl.calls, isEmpty);
    expect(find.text('1. a pet'), findsOneWidget);
    expect(find.byKey(const Key('lookup-mode-toggle')), findsOneWidget);
    expect(find.byKey(const Key('lookup-known-toggle')), findsOneWidget);
  });

  testWidgets('a phrase goes to DeepL; no toggle, no level, no dictionary '
      'choice', (tester) async {
    final f = _Fixture();
    await f.open(tester, _phraseQuery);

    expect(f.selection.calls, isEmpty);
    expect(f.deepl.calls.single.text, _phrase);
    expect(f.deepl.calls.single.mode, LookupMode.enRu);
    expect(f.deepl.calls.single.sentence, 'Then he gave up.');
    expect(find.text(_phrase), findsOneWidget);
    expect(find.text('Он сдался'), findsOneWidget);
    expect(find.byKey(const Key('lookup-known-toggle')), findsNothing);
    expect(find.text('DeepL'), findsOneWidget);
    expect(find.byKey(const Key('lookup-mode-toggle')), findsNothing);
    expect(find.text('A1'), findsNothing);
    expect(find.byKey(const Key('lookup-provider')), findsNothing);
  });

  testWidgets('a long phrase is folded after three lines', (tester) async {
    final f = _Fixture();
    final long = List.filled(60, 'word').join(' ');
    await f.open(
      tester,
      LookupQuery(text: long, mode: LookupMode.enEn, locator: _place),
    );

    final text = tester.widget<Text>(find.text(long));
    expect(text.maxLines, 3);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('no key: the message and the settings button', (tester) async {
    final f = _Fixture();
    f.deepl.failure = const ProviderUnavailable('no_key');
    await f.open(tester, _phraseQuery);

    expect(
      find.text('Phrase translation needs a DeepL API key'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsNothing);

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(f.settingsOpened, 1);
    expect(find.byType(LookupSheet), findsNothing);
    expect(await f.count(), 0);
  });

  testWidgets('an error: a message by code and Retry', (tester) async {
    final f = _Fixture();
    f.deepl.failure = const ProviderUnavailable('network');
    await f.open(tester, _phraseQuery);

    expect(
      find.text('No connection. Check the network and try again.'),
      findsOneWidget,
    );
    expect(find.text('Open settings'), findsNothing);

    f.deepl.failure = null;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Он сдался'), findsOneWidget);
    expect(f.deepl.calls, hasLength(2));
    await tester.pump(minLookupViewDuration);
    expect(await f.count(), 1);
  });

  testWidgets('two sentences: a message, no Retry, no request', (tester) async {
    final f = _Fixture();
    await f.open(
      tester,
      const LookupQuery(
        text: 'He gave up. Then he left.',
        mode: LookupMode.enEn,
        locator: _place,
      ),
    );

    expect(find.text('Select one sentence at most'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Open settings'), findsNothing);
    expect(f.deepl.calls, isEmpty);

    await tester.pump(const Duration(seconds: 10));
    expect(await f.count(), 0);
  });

  testWidgets('an error is never recorded', (tester) async {
    final f = _Fixture();
    f.deepl.failure = const ProviderUnavailable('quota');
    await f.open(tester, _phraseQuery);

    await tester.pump(const Duration(seconds: 10));

    expect(
      find.text('The DeepL quota of this key is used up.'),
      findsOneWidget,
    );
    expect(await f.count(), 0);
  });

  testWidgets('on screen for 2 s: one entry in the phrase journal', (
    tester,
  ) async {
    final f = _Fixture();
    await f.open(tester, _phraseQuery);

    await tester.pump(const Duration(milliseconds: 1900));
    expect(await f.count(), 0);

    await tester.pump(const Duration(milliseconds: 200));
    final entries = await f.journal.byBook(const BookId('b1'));
    expect(entries, hasLength(1));
    expect(entries.single.text, _phrase);
    expect(entries.single.translation, 'Он сдался');
    expect(entries.single.provider, _deepl);
    expect(entries.single.sentence, 'Then he gave up.');
    expect(entries.single.locator, _place);

    await tester.pump(const Duration(seconds: 10));
    expect(await f.count(), 1);
    expect(f.selection.calls, isEmpty);
  });

  testWidgets('closed before 2 s: nothing is recorded', (tester) async {
    final f = _Fixture();
    await f.open(tester, _phraseQuery);

    await tester.pump(const Duration(milliseconds: 1900));
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));

    expect(find.byType(LookupSheet), findsNothing);
    expect(await f.count(), 0);
  });
}
