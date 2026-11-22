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
    Routes.cheatsheetFor('b2'): ['Cheat sheet', 'bookId: b2'],
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
