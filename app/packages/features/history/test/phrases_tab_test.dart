import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:features_history/features_history.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late FakeBookRepository books;
  late FakeLookupJournal journal;
  late FakeTermRepository terms;
  late FakePhraseJournal phrases;
  late List<Locator> opened;

  setUp(() {
    books = FakeBookRepository();
    journal = FakeLookupJournal();
    terms = FakeTermRepository();
    phrases = FakePhraseJournal();
    opened = [];
  });

  Locator locator(String bookId) => Locator(
    book: BookId(bookId),
    chapter: const ChapterRef(href: 'c.xhtml', index: 0),
    progression: 0.5,
  );

  PhraseLookup phrase(
    String id,
    String text, {
    required DateTime at,
    String bookId = 'a',
    String? sentence,
  }) => PhraseLookup(
    id: PhraseLookupId(id),
    text: text,
    translation: 'tr of $text',
    provider: const ProviderId('deepl'),
    at: at,
    locator: locator(bookId),
    sentence: sentence,
  );

  Future<void> pumpPhrases(WidgetTester tester) async {
    await books.save(
      Book(
        id: const BookId('a'),
        metadata: const BookMetadata(title: 'Dune'),
        format: BookFormat.epub,
        filePath: '/x/a.epub',
        contentHash: 'ha',
        addedAt: DateTime.utc(2024),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWithValue(books),
          lookupJournalProvider.overrideWithValue(journal),
          termRepositoryProvider.overrideWithValue(terms),
          phraseJournalProvider.overrideWithValue(phrases),
        ],
        child: MaterialApp(home: HistoryScreen(onOpenLocation: opened.add)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openPhrasesTab(WidgetTester tester) async {
    await tester.tap(find.text('Phrases'));
    await tester.pumpAndSettle();
  }

  testWidgets('tabs switch between words and phrases', (tester) async {
    await phrases.record(phrase('p1', 'gave up', at: DateTime.utc(2024)));
    await pumpPhrases(tester);

    expect(find.text('No lookups yet.'), findsOneWidget);
    expect(find.text('gave up'), findsNothing);

    await openPhrasesTab(tester);
    expect(find.text('gave up'), findsOneWidget);
    expect(find.text('No lookups yet.'), findsNothing);

    await tester.tap(find.text('Words'));
    await tester.pumpAndSettle();
    expect(find.text('No lookups yet.'), findsOneWidget);
  });

  testWidgets('shows phrase, translation, book, date and two-line sentence', (
    tester,
  ) async {
    await phrases.record(
      phrase(
        'p1',
        'gave up',
        at: DateTime.utc(2024, 1, 1, 10, 5),
        sentence: 'He gave up.',
      ),
    );
    await pumpPhrases(tester);
    await openPhrasesTab(tester);

    expect(find.text('gave up'), findsOneWidget);
    expect(find.text('tr of gave up'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'^Dune · 2024-01-01 \d\d:\d\d$')),
      findsOneWidget,
    );
    final sentence = tester.widget<Text>(find.text('He gave up.'));
    expect(sentence.maxLines, 2);
  });

  testWidgets('lists the newest first and picks up new entries live', (
    tester,
  ) async {
    await phrases.record(phrase('p1', 'old one', at: DateTime.utc(2024)));
    await pumpPhrases(tester);
    await openPhrasesTab(tester);

    await phrases.record(phrase('p2', 'new one', at: DateTime.utc(2024, 2)));
    await tester.pumpAndSettle();

    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title! as Text).data)
        .toList();
    expect(titles, ['new one', 'old one']);
  });

  testWidgets('tapping a phrase reports its locator', (tester) async {
    await phrases.record(phrase('p1', 'gave up', at: DateTime.utc(2024)));
    await pumpPhrases(tester);
    await openPhrasesTab(tester);

    await tester.tap(find.text('gave up'));
    expect(opened, [locator('a')]);
  });

  testWidgets('swipe deletes a phrase and Undo restores it', (tester) async {
    await phrases.record(phrase('p1', 'gave up', at: DateTime.utc(2024)));
    await pumpPhrases(tester);
    await openPhrasesTab(tester);

    await tester.drag(find.text('gave up'), const Offset(800, 0));
    await tester.pumpAndSettle();
    expect(find.text('gave up'), findsNothing);
    expect(await phrases.byBook(const BookId('a')), isEmpty);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('gave up'), findsOneWidget);
    expect(await phrases.byBook(const BookId('a')), hasLength(1));
  });

  testWidgets('shows a hint when there are no phrases', (tester) async {
    await pumpPhrases(tester);
    await openPhrasesTab(tester);
    expect(
      find.text('Select several words while reading to translate a phrase'),
      findsOneWidget,
    );
  });
}
