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

void main() {
  const id = BookId('b1');
  late FakeBookRepository books;
  late FakeBookFormatAdapter adapter;
  late FakeProfileRepository profiles;
  late _FakeGenerator generator;
  late FakeLookupProvider dictionary;

  Locator at(int chapter, double progression) => Locator(
    book: id,
    chapter: ChapterRef(href: 'chapter${chapter + 1}.xhtml', index: chapter),
    progression: progression,
  );

  setUp(() async {
    books = FakeBookRepository();
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
          termRepositoryProvider.overrideWithValue(FakeTermRepository()),
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
    // Two rounds: the sheet, then the glosses of its rows.
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
    expect(find.text('C1'), findsOneWidget);
    expect(find.text('B2'), findsOneWidget);
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
}
