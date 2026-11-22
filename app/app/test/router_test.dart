import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:my_reader_app/bootstrap.dart';
import 'package:my_reader_app/router.dart';

void main() {
  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(bootstrap());
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
  }

  testWidgets('starts on the library', (tester) async {
    await pumpApp(tester);
    expect(find.widgetWithText(AppBar, 'Library'), findsOneWidget);
  });

  final cases = <String, List<String>>{
    Routes.library: ['Library'],
    Routes.settings: ['Settings'],
  };

  for (final MapEntry(key: location, value: texts) in cases.entries) {
    testWidgets('route $location opens its stub', (tester) async {
      final container = await pumpApp(tester);
      container.read(routerProvider).go(location);
      await tester.pumpAndSettle();
      for (final text in texts) {
        expect(find.text(text), findsOneWidget);
      }
    });
  }

  testWidgets('route ${Routes.history} opens the history screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      bootstrap(
        overrides: [
          ...buildOverrides(),
          bookRepositoryProvider.overrideWithValue(FakeBookRepository()),
          lookupJournalProvider.overrideWithValue(FakeLookupJournal()),
          termRepositoryProvider.overrideWithValue(FakeTermRepository()),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold)),
    );
    container.read(routerProvider).go(Routes.history);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'History'), findsOneWidget);
    expect(find.text('No lookups yet.'), findsOneWidget);
  });

  testWidgets('route ${Routes.cheatsheet} opens the cheat sheet', (
    tester,
  ) async {
    const id = BookId('b2');
    final books = FakeBookRepository();
    await books.save(
      Book(
        id: id,
        metadata: const BookMetadata(title: 'Dune'),
        format: BookFormat.epub,
        filePath: '/x/b2.epub',
        contentHash: 'h',
        addedAt: DateTime.utc(2024),
      ),
    );
    final adapter = FakeBookFormatAdapter()
      ..register(
        '/x/b2.epub',
        const BookMetadata(title: 'Dune'),
        chapters: ['The spice must flow.'],
      );
    await tester.pumpWidget(
      bootstrap(
        overrides: [
          ...buildOverrides(),
          bookRepositoryProvider.overrideWithValue(books),
          progressRepositoryProvider.overrideWithValue(
            FakeProgressRepository(),
          ),
          bookFormatsProvider.overrideWithValue([adapter]),
          profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
          termRepositoryProvider.overrideWithValue(FakeTermRepository()),
          lookupProvidersProvider.overrideWithValue(const []),
          cheatSheetGeneratorProvider.overrideWithValue(_OneItemGenerator()),
        ],
      ),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold)),
    );
    container.read(routerProvider).go(Routes.cheatsheetFor('b2'));
    for (var i = 0; i < 2; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.text('Следующие ~10 стр.'), findsOneWidget);
    expect(find.text('spice'), findsOneWidget);
    expect(find.text('Читать'), findsOneWidget);
  });

  testWidgets('light and dark themes follow the system', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await pumpApp(tester);
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.light,
    );
  });
}

class _OneItemGenerator implements CheatSheetGenerator {
  @override
  Future<CheatSheet> generate({
    required String text,
    required Locator from,
    required Locator to,
    required CefrLevel userLevel,
    Set<String> knownTerms = const {},
    CancelToken? cancel,
  }) async => CheatSheet(
    from: from,
    to: to,
    items: const [CheatSheetItem(text: 'spice', kind: CheatSheetItemKind.word)],
  );
}
