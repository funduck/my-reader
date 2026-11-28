import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:features_history/features_history.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _NoLevels implements LevelDictionary {
  @override
  WordLevel levelOf(String lemma, {String? pos}) =>
      const WordLevel(CefrLevel.unknown);
}

void main() {
  late FakeBookRepository books;
  late FakeLookupJournal journal;
  late FakeTermRepository terms;

  setUp(() {
    books = FakeBookRepository();
    journal = FakeLookupJournal();
    terms = FakeTermRepository();
  });

  Future<void> lookup(String id, String word, {required DateTime at}) =>
      journal.record(
        LookupEvent(
          id: LookupEventId(id),
          query: LookupQuery(text: word, mode: LookupMode.enEn),
          result: const LookupResult(
            provider: ProviderId('p'),
            senses: [Sense(text: 'x')],
          ),
          at: at,
        ),
      );

  Future<void> term(
    String word, {
    List<String> events = const [],
    TermStatus status = TermStatus.learning,
  }) => terms.save(
    Term(
      id: TermId('t-$word'),
      normalized: word,
      language: 'en',
      lookupCount: events.length,
      eventIds: [for (final id in events) LookupEventId(id)],
      status: status,
    ),
  );

  Future<TermStatus?> status(String word) async =>
      (await terms.find(word, 'en'))?.status;

  Future<void> pumpHistory(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWithValue(books),
          lookupJournalProvider.overrideWithValue(journal),
          termRepositoryProvider.overrideWithValue(terms),
          levelDictionaryProvider.overrideWithValue(_NoLevels()),
          idGeneratorProvider.overrideWithValue(SeqIdGenerator()),
        ],
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  final filter = find.byKey(const Key('history-known-filter'));
  final unmark = find.byKey(const Key('history-unmark-known'));

  Future<void> seed() async {
    await lookup('e1', 'sand', at: DateTime.utc(2024));
    await lookup('e2', 'worm', at: DateTime.utc(2024, 2));
    await term('sand', events: ['e1']);
    await term('worm', events: ['e2'], status: TermStatus.known);
    // Marked from the cheat sheet, never looked up.
    await term('spice', status: TermStatus.known);
  }

  testWidgets('the filter lists known terms, also those never looked up', (
    tester,
  ) async {
    await seed();
    await pumpHistory(tester);
    // All: lookups newest first, then the term with no lookup.
    final all = tester
        .widgetList<ListTile>(
          find.descendant(
            of: find.byType(ListView).last,
            matching: find.byType(ListTile),
          ),
        )
        .map((t) => (t.title! as Text).data)
        .toList();
    expect(all, ['worm', 'sand', 'spice']);

    await tester.tap(filter);
    await tester.pumpAndSettle();
    expect(find.text('worm'), findsOneWidget);
    expect(find.text('spice'), findsOneWidget);
    expect(find.text('sand'), findsNothing);
    // A known term has the check; one without lookups has no counter.
    expect(unmark, findsNWidgets(2));
    expect(find.text('×1'), findsOneWidget);
    expect(find.text('×0'), findsNothing);

    await tester.tap(filter);
    await tester.pumpAndSettle();
    expect(find.text('sand'), findsOneWidget);
  });

  testWidgets('no known words shows its own hint', (tester) async {
    await lookup('e1', 'sand', at: DateTime.utc(2024));
    await term('sand', events: ['e1']);
    await pumpHistory(tester);
    await tester.tap(filter);
    await tester.pumpAndSettle();
    expect(find.text('No known words.'), findsOneWidget);
    expect(unmark, findsNothing);
  });

  testWidgets('a term that is not known has no check', (tester) async {
    await lookup('e1', 'sand', at: DateTime.utc(2024));
    await term('sand', events: ['e1']);
    await pumpHistory(tester);
    expect(find.text('sand'), findsOneWidget);
    expect(unmark, findsNothing);
  });

  testWidgets('unmarking makes the term learning; Undo marks it again', (
    tester,
  ) async {
    await seed();
    await pumpHistory(tester);
    await tester.tap(filter);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ExpansionTile, 'worm'),
        matching: unmark,
      ),
    );
    await tester.pumpAndSettle();
    expect(await status('worm'), TermStatus.learning);
    expect(find.text('worm'), findsNothing);
    expect(find.textContaining('worm'), findsOneWidget); // the SnackBar
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(await status('worm'), TermStatus.known);
    expect(find.text('worm'), findsOneWidget);
    // The lookups of the term are untouched.
    expect((await terms.find('worm', 'en'))?.lookupCount, 1);
  });

  testWidgets('the Undo snack bar goes away on its own', (tester) async {
    await seed();
    await pumpHistory(tester);
    await tester.tap(filter);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ExpansionTile, 'worm'),
        matching: unmark,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('a term with no lookups leaves the history when unmarked, '
      'Undo brings it back', (tester) async {
    await seed();
    await pumpHistory(tester);
    expect(find.text('spice'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'spice'),
        matching: unmark,
      ),
    );
    await tester.pumpAndSettle();
    expect(await status('spice'), TermStatus.learning);
    expect(find.text('spice'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(await status('spice'), TermStatus.known);
    expect(find.text('spice'), findsOneWidget);
  });

  testWidgets('the book filter and the known filter work together', (
    tester,
  ) async {
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
    await seed();
    await pumpHistory(tester);
    await tester.tap(filter);
    await tester.pumpAndSettle();
    expect(find.text('spice'), findsOneWidget);

    // No lookup is in the book, so nothing is left.
    await tester.tap(find.widgetWithText(ToggleButton, 'Dune'));
    await tester.pumpAndSettle();
    expect(find.text('spice'), findsNothing);
    expect(find.text('worm'), findsNothing);
  });

  testWidgets('the filter and the row mark are common toggle buttons', (
    tester,
  ) async {
    await seed();
    await pumpHistory(tester);

    // Off: no check mark. On: the check mark appears.
    expect(tester.widget<ToggleButton>(filter).selected, isFalse);
    expect(
      find.descendant(of: filter, matching: find.byIcon(Icons.check)),
      findsNothing,
    );
    await tester.tap(filter);
    await tester.pumpAndSettle();
    expect(tester.widget<ToggleButton>(filter).selected, isTrue);
    expect(
      find.descendant(of: filter, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );

    // The mark on a known row is the same toggle, switched on.
    expect(tester.widget<ToggleButton>(unmark.first).selected, isTrue);
    expect(find.byType(Chip), findsNothing);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
  });
}
