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
  final List<({String text, Locator from, Set<String> known})> calls = [];

  @override
  Future<CheatSheet> generate({
    required String text,
    required Locator from,
    required Locator to,
    Set<String> knownTerms = const {},
    CancelToken? cancel,
  }) async {
    calls.add((text: text, from: from, known: knownTerms));
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

  Locator at(int chapter, double progression) => Locator(
    book: id,
    chapter: ChapterRef(href: 'chapter${chapter + 1}.xhtml', index: chapter),
    progression: progression,
  );

  setUp(() async {
    books = FakeBookRepository();
    terms = FakeTermRepository();
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
    expect(find.text('До конца главы'), findsOneWidget);
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

    testWidgets('a failed mark puts the row back', (tester) async {
      await limitTo(2);
      terms = _FailingTerms();
      await open(tester, from: at(0, 0));
      await tester.tap(find.byKey(const Key('cheatsheet-known-w1')));
      await settle(tester);
      expect(shownWords(tester), ['w1', 'w2']);
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

class _FailingTerms extends FakeTermRepository {
  @override
  Future<void> save(Term term) => Future<void>.error(StateError('disk'));
}
