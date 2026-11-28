import 'dart:async';

import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_cheatsheet/features_cheatsheet.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _FakeGenerator implements CheatSheetGenerator {
  new(this.items);

  final List<CheatSheetItem> items;
  final List<({String text, Locator from, Locator to, Set<String> known})>
  calls = [];

  @override
  Future<CheatSheet> generate({
    required String text,
    required Locator from,
    required Locator to,
    Set<String> knownTerms = const {},
    CancelToken? cancel,
  }) async {
    calls.add((text: text, from: from, to: to, known: knownTerms));
    return CheatSheet(from: from, to: to, items: items);
  }
}

/// Words are runs of letters; the lemma is the lower-cased word.
class _Analyzer implements TextAnalyzer {
  @override
  List<SentenceSpan> sentences(String text) => [SentenceSpan(0, text.length)];

  @override
  List<TextToken> tokens(String text) => [
    for (final m in RegExp('[A-Za-z0-9]+').allMatches(text))
      TextToken(m[0]!, m.start, m.end),
  ];

  @override
  String lemma(String word) => word.toLowerCase();
}

class _NoLevels implements LevelDictionary {
  @override
  WordLevel levelOf(String lemma, {String? pos}) =>
      const WordLevel(CefrLevel.unknown);
}

void main() {
  const id = BookId('b1');
  late FakeBookRepository books;
  late FakeBookFormatAdapter adapter;
  late FakeProfileRepository profiles;
  late _FakeGenerator generator;
  late FakeLookupProvider dictionary;
  late FakeTermRepository terms;
  late FakeCheatSheetLog log;
  late FakeClock clock;

  Locator at(int chapter, double progression) => Locator(
    book: id,
    chapter: ChapterRef(href: 'chapter${chapter + 1}.xhtml', index: chapter),
    progression: progression,
  );

  setUp(() async {
    books = FakeBookRepository();
    terms = FakeTermRepository();
    log = FakeCheatSheetLog();
    clock = FakeClock(DateTime.utc(2024, 3, 4, 5, 6));
    adapter = FakeBookFormatAdapter()
      ..register(
        '/x/b1.epub',
        const BookMetadata(title: 'Dune'),
        chapters: ['The spice must flow.', 'Second chapter.'],
      );
    profiles = FakeProfileRepository(const UserProfile(level: CefrLevel.b1));
    generator = _FakeGenerator(const [
      CheatSheetItem(
        text: 'spice',
        kind: CheatSheetItemKind.word,
        level: CefrLevel.c1,
        example: 'The spice must flow.',
      ),
      CheatSheetItem(
        text: 'flow',
        kind: CheatSheetItemKind.word,
        level: CefrLevel.b2,
        translation: 'течь',
        example: 'The spice must flowing.',
      ),
    ]);
    dictionary = FakeLookupProvider(
      id: const ProviderId('fake'),
      answers: {
        'spice': const LookupResult(
          provider: ProviderId('fake'),
          senses: [
            Sense(text: 'a pungent substance'),
            Sense(text: 'second'),
          ],
        ),
      },
    );
    await books.save(
      Book(
        id: id,
        metadata: const BookMetadata(title: 'Dune'),
        format: BookFormat.epub,
        filePath: '/x/b1.epub',
        contentHash: 'h',
        addedAt: DateTime.utc(2024),
      ),
    );
  });

  var reads = 0;
  final taps = <LookupQuery>[];

  Future<void> open(WidgetTester tester, {Locator? from}) async {
    reads = 0;
    taps.clear();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWithValue(books),
          progressRepositoryProvider.overrideWithValue(
            FakeProgressRepository(),
          ),
          bookFormatsProvider.overrideWithValue([adapter]),
          profileRepositoryProvider.overrideWithValue(profiles),
          termRepositoryProvider.overrideWithValue(terms),
          cheatSheetLogProvider.overrideWithValue(log),
          clockProvider.overrideWithValue(clock),
          textAnalyzerProvider.overrideWithValue(_Analyzer()),
          levelDictionaryProvider.overrideWithValue(_NoLevels()),
          idGeneratorProvider.overrideWithValue(SeqIdGenerator(prefix: 't')),
          cheatSheetGeneratorProvider.overrideWithValue(generator),
          lookupProvidersProvider.overrideWithValue([dictionary]),
        ],
        child: MaterialApp(
          home: CheatSheetScreen(
            bookId: id,
            from: from,
            onRead: () => reads++,
            onWordTap: (_, query) => taps.add(query),
          ),
        ),
      ),
    );
    // Two rounds: the sheet with the profile, then the glosses of the rows.
    for (var i = 0; i < 2; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  testWidgets('lists words with level, first sense and the example', (
    tester,
  ) async {
    await open(tester, from: at(0, 0));
    expect(find.text('Следующие ~10 стр.'), findsOneWidget);
    expect(find.text('spice'), findsOneWidget);
    // The level pickers have the same labels; look at the rows only.
    Finder inRows(String text) =>
        find.descendant(of: find.byType(ListTile), matching: find.text(text));
    expect(inRows('C1'), findsOneWidget);
    expect(inRows('B2'), findsOneWidget);
    // First sense from the provider, translation of the item as it is.
    expect(find.text('a pungent substance'), findsOneWidget);
    expect(find.text('second'), findsNothing);
    expect(find.text('течь'), findsOneWidget);
    // The sentence comes with the word in bold, as its own span.
    final example = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText() == 'The spice must flow.',
    );
    expect(example, findsOneWidget);
    final bold = <String>[];
    tester.widget<RichText>(example).text.visitChildren((span) {
      if (span is TextSpan && span.style?.fontWeight == FontWeight.bold) {
        bold.add(span.text!);
      }
      return true;
    });
    expect(bold, ['spice']);
    expect(generator.calls.single.from.chapter.index, 0);
    expect(generator.calls.single.text, startsWith('The spice'));
  });

  testWidgets('a chapter scope is titled "до конца главы"', (tester) async {
    await profiles.save(
      const UserProfile(level: CefrLevel.b1, scope: CheatSheetChapter()),
    );
    await open(tester, from: at(0, 0));
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('До конца главы'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('without a locator it starts from the book start', (
    tester,
  ) async {
    await open(tester);
    expect(generator.calls.single.from.chapter.index, 0);
  });

  testWidgets('tapping a word passes a query with its sentence', (
    tester,
  ) async {
    await open(tester, from: at(0, 0));
    await tester.tap(find.text('spice'));
    expect(taps, hasLength(1));
    expect(taps.single.text, 'spice');
    expect(taps.single.sentence, 'The spice must flow.');
    expect(taps.single.mode, LookupMode.enEn);
    expect(taps.single.locator, generator.calls.single.from);
  });

  testWidgets('the Read button calls onRead', (tester) async {
    await open(tester, from: at(0, 0));
    await tester.tap(find.text('Читать'));
    expect(reads, 1);
  });

  testWidgets('an empty sheet says so and keeps the Read button', (
    tester,
  ) async {
    generator = _FakeGenerator(const []);
    await open(tester, from: at(0, 0));
    expect(find.text('Незнакомых слов не нашлось.'), findsOneWidget);
    expect(find.text('Читать'), findsOneWidget);
  });

  testWidgets('a missing book shows an error', (tester) async {
    books = FakeBookRepository();
    await open(tester, from: at(0, 0));
    expect(find.text('Не удалось подготовить разминку.'), findsOneWidget);
    expect(find.text('Читать'), findsOneWidget);
  });

  CheatSheetItem word(
    String text, {
    CefrLevel level = CefrLevel.c1,
    double? zipf,
  }) => CheatSheetItem(
    text: text,
    kind: CheatSheetItemKind.word,
    level: level,
    zipf: zipf,
    translation: 'tr-$text',
    example: 'Say $text now.',
  );

  List<String> shownWords(WidgetTester tester) => [
    for (final w in tester.widgetList<Text>(find.byType(Text)))
      if (w.data != null && w.data!.startsWith('w')) w.data!,
  ];

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  String limitText(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('cheatsheet-limit')))
      .controller!
      .text;

  /// Types [text] into the limit field and presses Enter.
  Future<void> enterLimit(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('cheatsheet-limit')), text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
  }

  group('level and limit', () {
    setUp(() {
      generator = _FakeGenerator([
        word('w1', level: CefrLevel.b2, zipf: 5),
        word('w2', zipf: 4.5),
        word('w3', level: CefrLevel.b2, zipf: 3.5),
        word('w4', level: CefrLevel.b1, zipf: 3),
        word('w5', zipf: 2),
      ]);
    });

    testWidgets('a limit from the profile cuts the list by frequency', (
      tester,
    ) async {
      await profiles.save(
        const UserProfile(level: CefrLevel.a2, cheatSheetLimit: 2),
      );
      await open(tester, from: at(0, 0));
      expect(shownWords(tester), ['w1', 'w2']);
    });

    testWidgets('the frequency threshold of the profile shortens the list', (
      tester,
    ) async {
      await profiles.save(
        const UserProfile(
          level: CefrLevel.a2,
          highlights: HighlightPrefs(minFrequencyBars: 4),
        ),
      );
      await open(tester, from: at(0, 0));
      // Bars: w1 5, w2 4, w3 3, w4 3, w5 2.
      expect(shownWords(tester), ['w1', 'w2']);
    });

    testWidgets('changing the level and the limit keeps the sheet', (
      tester,
    ) async {
      await open(tester, from: at(0, 0));
      // The profile of the test: B1, limit 10. w4 is B1, not above B1.
      expect(shownWords(tester), ['w1', 'w2', 'w3', 'w5']);

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('cheatsheet-level')),
          matching: find.text('A2'),
        ),
      );
      await settle(tester);
      expect(shownWords(tester), ['w1', 'w2', 'w3', 'w4', 'w5']);
      expect((await profiles.get()).level, CefrLevel.a2);

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('cheatsheet-level')),
          matching: find.text('B2'),
        ),
      );
      await settle(tester);
      expect(shownWords(tester), ['w2', 'w5']);

      await enterLimit(tester, '3');
      expect((await profiles.get()).cheatSheetLimit, 3);
      await enterLimit(tester, '15');
      expect((await profiles.get()).cheatSheetLimit, 15);
      // Nothing above reopened the book or ran the generator again.
      expect(generator.calls, hasLength(1));
    });

    testWidgets('the field starts at 10; 7 and Enter shows 7 rows', (
      tester,
    ) async {
      generator = _FakeGenerator([
        for (var i = 10; i < 40; i++) word('w$i', zipf: 6 - i / 10),
      ]);
      await open(tester, from: at(0, 0));
      expect(limitText(tester), '10');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CheatSheetScreen)),
      );
      final request = (bookId: id, from: at(0, 0));
      expect(
        container.read(cheatSheetItemsProvider(request)).value,
        hasLength(10),
      );

      await enterLimit(tester, '7');
      expect((await profiles.get()).cheatSheetLimit, 7);
      expect(
        container.read(cheatSheetItemsProvider(request)).value,
        hasLength(7),
      );
      expect(generator.calls, hasLength(1));
    });

    testWidgets('an empty or zero value returns to the saved number', (
      tester,
    ) async {
      await open(tester, from: at(0, 0));
      await enterLimit(tester, '');
      expect(limitText(tester), '10');
      expect((await profiles.get()).cheatSheetLimit, 10);
      await enterLimit(tester, '0');
      expect(limitText(tester), '10');
      expect((await profiles.get()).cheatSheetLimit, 10);
    });

    testWidgets('more than 500 becomes 500; the field keeps digits only', (
      tester,
    ) async {
      await open(tester, from: at(0, 0));
      await enterLimit(tester, '999');
      expect(limitText(tester), '500');
      expect((await profiles.get()).cheatSheetLimit, 500);

      await tester.enterText(find.byKey(const Key('cheatsheet-limit')), '1a2');
      expect(limitText(tester), '12');
    });

    testWidgets('losing the focus saves the value', (tester) async {
      await open(tester, from: at(0, 0));
      await tester.enterText(find.byKey(const Key('cheatsheet-limit')), '4');
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(tester);
      expect((await profiles.get()).cheatSheetLimit, 4);
    });
  });

  group('known', () {
    setUp(() {
      generator = _FakeGenerator([
        word('w1', zipf: 5),
        word('w2', zipf: 4),
        word('w3', zipf: 3),
      ]);
    });

    Future<void> limitTo(int limit) async {
      await profiles.save(
        UserProfile(level: CefrLevel.b1, cheatSheetLimit: limit),
      );
    }

    testWidgets('"Знаю" removes the row and the next word takes its place', (
      tester,
    ) async {
      await limitTo(2);
      await open(tester, from: at(0, 0));
      expect(shownWords(tester), ['w1', 'w2']);

      await tester.tap(find.byKey(const Key('cheatsheet-known-w1')));
      await settle(tester);

      expect(shownWords(tester), ['w2', 'w3']);
      final term = (await tester.runAsync(() => terms.watchAll().first))!
          .single;
      expect(term.normalized, 'w1');
      expect(term.status, TermStatus.known);
      expect(generator.calls, hasLength(1));
    });

    testWidgets('Undo brings the word back and makes it learning', (
      tester,
    ) async {
      await limitTo(2);
      await open(tester, from: at(0, 0));
      await tester.tap(find.byKey(const Key('cheatsheet-known-w1')));
      await settle(tester);
      // Let the snack bar slide in.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester);

      expect(shownWords(tester), ['w1', 'w2']);
      final term = (await tester.runAsync(() => terms.watchAll().first))!
          .single;
      expect(term.status, TermStatus.learning);
      expect(generator.calls, hasLength(1));
    });

    testWidgets('the Undo snack bar goes away on its own', (tester) async {
      await limitTo(2);
      await open(tester, from: at(0, 0));
      await tester.tap(find.byKey(const Key('cheatsheet-known-w1')));
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Undo'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('a failed mark puts the row back', (tester) async {
      await limitTo(2);
      terms = _FailingTerms();
      await open(tester, from: at(0, 0));
      await tester.tap(find.byKey(const Key('cheatsheet-known-w1')));
      await settle(tester);
      expect(shownWords(tester), ['w1', 'w2']);
    });
  });

  group('last shown list', () {
    setUp(() {
      generator = _FakeGenerator([
        word('w1', level: CefrLevel.b2, zipf: 5),
        word('w2', zipf: 4.5),
        word('w3', level: CefrLevel.b2, zipf: 3.5),
        word('w4', level: CefrLevel.b1, zipf: 3),
        word('w5', zipf: 2),
      ]);
    });

    CheatSheetSnapshot snapshot(List<String> lemmas, {DateTime? at}) =>
        CheatSheetSnapshot(
          book: id,
          shownAt: at ?? DateTime.utc(2024, 3, 4, 5, 6),
          lemmas: lemmas,
        );

    Future<CheatSheetSnapshot?> stored(WidgetTester tester) =>
        tester.runAsync(() => log.watch(id).first).then((s) => s);

    /// Taps "Читать" and lets the write and the call of `onRead` finish.
    Future<void> pressRead(WidgetTester tester) async {
      final button = find.text('Читать');
      await tester.scrollUntilVisible(
        button,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(button);
      await settle(tester);
    }

    testWidgets('opening and going back saves nothing', (tester) async {
      await open(tester, from: at(0, 0));
      expect(shownWords(tester), ['w1', 'w2', 'w3', 'w5']);
      // A change of the list on screen writes nothing either.
      await enterLimit(tester, '2');
      await tester.tap(find.byKey(const Key('cheatsheet-known-w1')));
      await settle(tester);
      expect(log.saved, isEmpty);
      expect(await stored(tester), isNull);
      expect(reads, 0);
    });

    testWidgets('a new level and "Читать" save one snapshot of the list', (
      tester,
    ) async {
      await open(tester, from: at(0, 0));
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('cheatsheet-level')),
          matching: find.text('B2'),
        ),
      );
      await settle(tester);
      clock.advance(const Duration(minutes: 1));

      await pressRead(tester);

      expect(shownWords(tester), ['w2', 'w5']);
      expect(log.saved, [
        snapshot(['w2', 'w5'], at: DateTime.utc(2024, 3, 4, 5, 7)),
      ]);
      expect(await stored(tester), log.saved.single);
      expect(reads, 1);
    });

    testWidgets('the limit and "Знаю" are in the snapshot', (tester) async {
      await open(tester, from: at(0, 0));
      await enterLimit(tester, '2');
      await tester.tap(find.byKey(const Key('cheatsheet-known-w1')));
      await settle(tester);

      await pressRead(tester);

      expect(log.saved.single.lemmas, ['w2', 'w3']);
    });

    testWidgets('an empty list is saved as an empty snapshot', (tester) async {
      generator = _FakeGenerator(const []);
      await open(tester, from: at(0, 0));
      expect(log.saved, isEmpty);

      await pressRead(tester);

      expect(log.saved, [snapshot([])]);
      expect(reads, 1);
    });

    testWidgets('an unbuilt sheet goes to the reader without a write', (
      tester,
    ) async {
      books = FakeBookRepository();
      await open(tester, from: at(0, 0));
      expect(find.text('Не удалось подготовить разминку.'), findsOneWidget);

      await pressRead(tester);

      expect(log.saved, isEmpty);
      expect(reads, 1);
    });

    testWidgets('a failing log still calls onRead', (tester) async {
      log = _FailingLog();
      await open(tester, from: at(0, 0));
      expect(shownWords(tester), ['w1', 'w2', 'w3', 'w5']);

      await pressRead(tester);

      expect(reads, 1);
    });

    testWidgets('onRead is called after the write', (tester) async {
      final gate = Completer<void>();
      log = _SlowLog(gate.future);
      await open(tester, from: at(0, 0));

      final button = find.text('Читать');
      await tester.scrollUntilVisible(
        button,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(button);
      await settle(tester);
      expect(reads, 0);

      gate.complete();
      await settle(tester);
      expect(reads, 1);
      expect(log.saved, hasLength(1));
    });

    testWidgets('"Читать" comes after the last row of the list', (
      tester,
    ) async {
      await open(tester, from: at(0, 0));
      final button = find.text('Читать');
      // Not pinned to the screen: the last row is above it in the list.
      await tester.scrollUntilVisible(
        button,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        tester.getTopLeft(button).dy,
        greaterThan(
          tester.getBottomLeft(find.byKey(const Key('cheatsheet-known-w5'))).dy,
        ),
      );
    });
  });

  group('piece of text', () {
    setUp(() {
      generator = _FakeGenerator([word('w1', zipf: 5), word('w2', zipf: 4)]);
    });

    testWidgets('"До конца главы" saves the scope and builds the sheet again', (
      tester,
    ) async {
      await open(tester, from: at(0, 0));
      expect(generator.calls, hasLength(1));
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('cheatsheet-scope')),
          matching: find.text('До конца главы'),
        ),
      );
      await settle(tester);
      expect((await profiles.get()).scope, const CheatSheetChapter());
      expect(generator.calls, hasLength(2));
      expect(find.byKey(const Key('cheatsheet-pages')), findsNothing);
      // The title and the list follow the new sheet.
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('До конца главы'),
        ),
        findsOneWidget,
      );
      expect(shownWords(tester), ['w1', 'w2']);

      await tester.tap(find.text('Страниц'));
      await settle(tester);
      expect((await profiles.get()).scope, CheatSheetScope.defaultScope);
      expect(generator.calls, hasLength(3));
    });

    testWidgets('a page count saves the scope; the level does not rebuild', (
      tester,
    ) async {
      await open(tester, from: at(0, 0));
      expect(find.text('Следующие ~10 стр.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cheatsheet-pages')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3').last);
      await settle(tester);
      expect((await profiles.get()).scope, const CheatSheetPages(3));
      expect(find.text('Следующие ~3 стр.'), findsOneWidget);
      expect(generator.calls, hasLength(2));
      // A shorter piece ends earlier.
      expect(
        generator.calls.last.to.progression,
        lessThanOrEqualTo(generator.calls.first.to.progression),
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('cheatsheet-level')),
          matching: find.text('A2'),
        ),
      );
      await settle(tester);
      expect(generator.calls, hasLength(2));
    });
  });

  group('looked-up words', () {
    Term seen(String text, {int lookups = 3}) => Term(
      id: TermId('seen-$text'),
      normalized: text,
      language: 'en',
      lookupCount: lookups,
      eventIds: const [],
    );

    setUp(() {
      // The profile level is b1: w1 (b1), w3 (no level) and w4 are not above
      // it; w2 is.
      generator = _FakeGenerator([
        word('w1', level: CefrLevel.b1, zipf: 5),
        word('w2', zipf: 4),
        word('w3', level: CefrLevel.unknown),
        word('w4', level: CefrLevel.a1, zipf: 3),
      ]);
    });

    testWidgets('a translated word stays in the list with a ×N mark', (
      tester,
    ) async {
      await terms.save(seen('w1'));
      await terms.save(seen('w3', lookups: 1));
      await open(tester, from: at(0, 0));

      expect(shownWords(tester), ['w1', 'w2', 'w3']);
      expect(find.byKey(const Key('cheatsheet-looked-up-w1')), findsOneWidget);
      expect(find.text('×3'), findsOneWidget);
      expect(find.text('×1'), findsOneWidget);
      expect(find.byKey(const Key('cheatsheet-looked-up-w2')), findsNothing);
      expect(find.byKey(const Key('cheatsheet-looked-up-w4')), findsNothing);
      // Nothing known is passed to the generator: the history is not hidden.
      expect(generator.calls.single.known, isEmpty);
    });

    testWidgets('the mark has a label and an icon, not only colour', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await terms.save(seen('w1'));
      await open(tester, from: at(0, 0));

      expect(find.bySemanticsLabel(RegExp('переводил: 3')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('cheatsheet-looked-up-w1')),
          matching: find.byIcon(Icons.translate),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('a word marked known is not shown, translated or not', (
      tester,
    ) async {
      await terms.save(seen('w1').copyWith(status: TermStatus.known));
      await open(tester, from: at(0, 0));

      expect(shownWords(tester), ['w2']);
      expect(generator.calls.single.known, {'w1'});
    });

    testWidgets('"Знаю" removes a translated word', (tester) async {
      await terms.save(seen('w1'));
      await open(tester, from: at(0, 0));
      expect(shownWords(tester), ['w1', 'w2']);

      await tester.tap(find.byKey(const Key('cheatsheet-known-w1')));
      await settle(tester);

      expect(shownWords(tester), ['w2']);
      final term = (await tester.runAsync(() => terms.find('w1', 'en')))!;
      expect(term.status, TermStatus.known);
      expect(term.lookupCount, 3);
      expect(generator.calls, hasLength(1));
    });
  });

  group('labels and buttons (T-126)', () {
    setUp(() {
      generator = _FakeGenerator([word('w1', zipf: 4.2), word('w2')]);
    });

    Finder inRow(String word, Finder matching) => find.descendant(
      of: find.widgetWithText(ListTile, word),
      matching: matching,
    );

    testWidgets('the level, the bars and the mark are common labels', (
      tester,
    ) async {
      await terms.save(
        const Term(
          id: TermId('seen-w1'),
          normalized: 'w1',
          language: 'en',
          lookupCount: 3,
          eventIds: [],
        ),
      );
      await open(tester, from: at(0, 0));

      final mark = find.byKey(const Key('cheatsheet-looked-up-w1'));
      expect(
        inRow(
          'w1',
          find.descendant(
            of: find.byType(LevelBadge),
            matching: find.widgetWithText(InfoLabel, 'C1'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(FrequencyBars),
          matching: find.byType(InfoLabel),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: mark, matching: find.byType(InfoLabel)),
        findsOneWidget,
      );
      // A label cannot be pressed.
      for (final label in [
        find.byType(LevelBadge),
        find.byType(FrequencyBars),
        mark,
      ]) {
        expect(
          find.descendant(of: label, matching: find.byType(InkWell)),
          findsNothing,
          reason: '$label',
        );
      }
    });

    testWidgets('"Знаю" is a bordered button with a check mark', (
      tester,
    ) async {
      await open(tester, from: at(0, 0));

      final button = find.byKey(const Key('cheatsheet-known-w1'));
      expect(tester.widget(button), isA<OutlinedButton>());
      expect(
        find.descendant(of: button, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: button, matching: find.text('Знаю')),
        findsOneWidget,
      );
    });
  });

  group('frequency bars', () {
    setUp(() {
      generator = _FakeGenerator([word('w1', zipf: 4.2), word('w2')]);
    });

    testWidgets('only a word with zipf has bars, with a label', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester, from: at(0, 0));
      expect(find.byType(FrequencyBars), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('частотность 4 из 5')),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });
}

class _FailingLog extends FakeCheatSheetLog {
  @override
  Future<void> save(CheatSheetSnapshot snapshot) =>
      Future<void>.error(StateError('disk'));
}

class _SlowLog extends FakeCheatSheetLog {
  new(this._gate);

  final Future<void> _gate;

  @override
  Future<void> save(CheatSheetSnapshot snapshot) async {
    await _gate;
    await super.save(snapshot);
  }
}

class _FailingTerms extends FakeTermRepository {
  @override
  Future<void> save(Term term) => Future<void>.error(StateError('disk'));
}
