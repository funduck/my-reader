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
  late List<Locator> opened;

  setUp(() {
    books = FakeBookRepository();
    journal = FakeLookupJournal();
    terms = FakeTermRepository();
    opened = [];
  });

  Book book(String id, String title) => Book(
    id: BookId(id),
    metadata: BookMetadata(title: title),
    format: BookFormat.epub,
    filePath: '/x/$id.epub',
    contentHash: 'h$id',
    addedAt: DateTime.utc(2024),
  );

  Locator locator(String bookId) => Locator(
    book: BookId(bookId),
    chapter: const ChapterRef(href: 'c.xhtml', index: 0),
    progression: 0.5,
  );

  Future<void> lookup(
    String id,
    String word, {
    required DateTime at,
    String? bookId,
    String? sentence,
    String gloss = 'a gloss',
  }) async {
    await journal.record(
      LookupEvent(
        id: LookupEventId(id),
        query: LookupQuery(
          text: word,
          mode: LookupMode.enEn,
          sentence: sentence,
          locator: bookId == null ? null : locator(bookId),
        ),
        result: LookupResult(
          provider: const ProviderId('p'),
          senses: [Sense(text: '$gloss of $word')],
        ),
        at: at,
      ),
    );
  }

  Future<void> term(String word, List<String> eventIds) => terms.save(
    Term(
      id: TermId('t-$word'),
      normalized: word,
      language: 'en',
      lookupCount: eventIds.length,
      eventIds: [for (final id in eventIds) LookupEventId(id)],
    ),
  );

  Future<void> pumpHistory(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWithValue(books),
          lookupJournalProvider.overrideWithValue(journal),
          termRepositoryProvider.overrideWithValue(terms),
        ],
        child: MaterialApp(home: HistoryScreen(onOpenLocation: opened.add)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows a hint when there is no history', (tester) async {
    await pumpHistory(tester);
    expect(find.text('No lookups yet.'), findsOneWidget);
  });

  testWidgets('lists terms newest first with count and book', (tester) async {
    await books.save(book('a', 'Dune'));
    await lookup('e1', 'sand', at: DateTime.utc(2024), bookId: 'a');
    await lookup('e2', 'worm', at: DateTime.utc(2024, 3), bookId: 'a');
    await lookup('e3', 'sand', at: DateTime.utc(2024, 2), bookId: 'a');
    await term('sand', ['e1', 'e3']);
    await term('worm', ['e2']);
    await pumpHistory(tester);

    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title! as Text).data)
        .toList();
    expect(titles, ['worm', 'sand']);
    expect(find.text('×2'), findsOneWidget);
    expect(find.text('×1'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ExpansionTile),
        matching: find.text('Dune'),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('word row shows word, book and counter, never the sense', (
    tester,
  ) async {
    await books.save(book('a', 'Dune'));
    await lookup(
      'e1',
      'sand',
      at: DateTime.utc(2024),
      bookId: 'a',
      gloss: '<p>loose <b>grains</b></p>',
    );
    await lookup('e2', 'worm', at: DateTime.utc(2024, 2));
    await term('sand', ['e1']);
    await term('worm', ['e2']);
    await pumpHistory(tester);

    expect(find.text('sand'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ExpansionTile, 'sand'),
        matching: find.text('Dune'),
      ),
      findsOneWidget,
    );
    expect(find.text('×1'), findsNWidgets(2));
    expect(find.textContaining('grains'), findsNothing);
    expect(find.textContaining('<'), findsNothing);
    expect(find.textContaining('a gloss'), findsNothing);
    // A word without a book has no subtitle.
    final worm = tester.widget<ExpansionTile>(
      find.widgetWithText(ExpansionTile, 'worm'),
    );
    expect(worm.subtitle, isNull);
  });

  testWidgets('expanding a term shows all contexts with dates', (tester) async {
    await books.save(book('a', 'Dune'));
    await lookup(
      'e1',
      'sand',
      at: DateTime.utc(2024, 1, 1, 10, 5),
      bookId: 'a',
      sentence: 'The sand was hot.',
    );
    await lookup(
      'e2',
      'sand',
      at: DateTime.utc(2024, 2, 1, 10, 5),
      bookId: 'a',
      sentence: 'Sand everywhere.',
    );
    await term('sand', ['e1', 'e2']);
    await pumpHistory(tester);

    expect(find.text('The sand was hot.'), findsNothing);
    await tester.tap(find.text('sand'));
    await tester.pumpAndSettle();
    expect(find.text('The sand was hot.'), findsOneWidget);
    expect(find.text('Sand everywhere.'), findsOneWidget);
    // Both contexts show a date and time.
    expect(
      find.textContaining(RegExp(r'^2024-0[12]-\d\d \d\d:\d\d$')),
      findsNWidgets(2),
    );
  });

  testWidgets('book filter keeps only terms and contexts of that book', (
    tester,
  ) async {
    await books.save(book('a', 'Dune'));
    await books.save(book('b', 'Emma'));
    await lookup('e1', 'sand', at: DateTime.utc(2024), bookId: 'a');
    await lookup('e2', 'ball', at: DateTime.utc(2024, 2), bookId: 'b');
    await lookup(
      'e3',
      'sand',
      at: DateTime.utc(2024, 3),
      bookId: 'b',
      sentence: 'Sand in Emma.',
    );
    await term('sand', ['e1', 'e3']);
    await term('ball', ['e2']);
    await pumpHistory(tester);
    expect(find.text('ball'), findsOneWidget);
    expect(find.text('sand'), findsOneWidget);

    await tester.tap(find.widgetWithText(ToggleButton, 'Dune'));
    await tester.pumpAndSettle();
    expect(find.text('ball'), findsNothing);
    expect(find.text('sand'), findsOneWidget);
    await tester.tap(find.text('sand'));
    await tester.pumpAndSettle();
    expect(find.text('Sand in Emma.'), findsNothing);

    await tester.tap(find.widgetWithText(ToggleButton, 'All books'));
    await tester.pumpAndSettle();
    expect(find.text('ball'), findsOneWidget);
  });

  testWidgets('tapping a context reports its locator', (tester) async {
    await books.save(book('a', 'Dune'));
    await lookup(
      'e1',
      'sand',
      at: DateTime.utc(2024),
      bookId: 'a',
      sentence: 'The sand was hot.',
    );
    await term('sand', ['e1']);
    await pumpHistory(tester);

    await tester.tap(find.text('sand'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('The sand was hot.'));
    expect(opened, [locator('a')]);
  });
}
