import 'package:core/domain_lookup.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:features_settings/features_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

void main() {
  final wiktionary = FakeProvider(
    'wiktionary.en-en',
    'Wiktionary',
    modes: {LookupMode.enEn},
  );
  final ruA = FakeProvider('stardict.a', 'Dictionary a');
  final ruB = FakeProvider('stardict.b', 'Dictionary b');

  test('orderedProviders puts the listed ids first', () {
    final all = [wiktionary, ruA, ruB];
    expect(orderedProviders(all, const []), all);
    expect(orderedProviders(all, [ruB.id, ruA.id]), [ruB, ruA, wiktionary]);
    expect(orderedProviders(all, [const ProviderId('gone'), ruB.id]), [
      ruB,
      wiktionary,
      ruA,
    ]);
  });

  group('screen', () {
    late FakeProfileRepository profile;
    late FakeDictionaryLibrary library;
    late List<String> picked;

    Future<void> pump(
      WidgetTester tester, {
      List<ImportedDictionary> dictionaries = const [],
    }) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      library = FakeDictionaryLibrary(dictionaries);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileRepositoryProvider.overrideWithValue(profile),
            packStoreProvider.overrideWithValue(FakePackStore()),
            dictionaryLibraryProvider.overrideWithValue(library),
            lookupProvidersProvider.overrideWithValue([wiktionary, ruA, ruB]),
            dictionaryFilePickerProvider.overrideWithValue(() async => picked),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    setUp(() {
      profile = FakeProfileRepository();
      picked = [];
    });

    testWidgets('lists dictionaries and the empty state', (tester) async {
      await pump(tester);
      expect(find.text('No dictionaries imported.'), findsOneWidget);

      await pump(tester, dictionaries: [fakeDictionary('a')]);
      expect(find.text('Dictionary a'), findsWidgets);
      expect(find.text('EN → RU · 100 words'), findsOneWidget);
    });

    testWidgets('imports the picked files for the chosen direction', (
      tester,
    ) async {
      picked = ['/x/a.ifo', '/x/a.idx', '/x/a.dict.dz'];
      await pump(tester);

      await tester.tap(find.byKey(const Key('import-dictionary')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mode-enEn')));
      await tester.pumpAndSettle();

      expect(library.imports, [(picked, LookupMode.enEn)]);
      expect(find.byKey(const Key('dictionary-imported-1')), findsOneWidget);
    });

    testWidgets('a cancelled dialog imports nothing', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('import-dictionary')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mode-enRu')), findsNothing);
      expect(library.imports, isEmpty);
    });

    testWidgets('shows a bad dictionary as a message', (tester) async {
      picked = ['/x/a.ifo'];
      await pump(tester);
      library.importFailure = const FormatException('Missing .idx file');

      await tester.tap(find.byKey(const Key('import-dictionary')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mode-enRu')));
      await tester.pumpAndSettle();

      expect(
        find.text('Not a StarDict dictionary: Missing .idx file'),
        findsOneWidget,
      );
      expect(library.dictionaries, isEmpty);
    });

    testWidgets('deleting asks first, then removes and drops the order', (
      tester,
    ) async {
      await profile.save(
        (await profile.get()).copyWith(providerOrder: [ruA.id, ruB.id]),
      );
      await pump(tester, dictionaries: [fakeDictionary('a')]);

      await tester.tap(find.byTooltip('Delete Dictionary a'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(library.removed, isEmpty);

      await tester.tap(find.byTooltip('Delete Dictionary a'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(library.removed, ['a']);
      expect(find.byKey(const Key('dictionary-a')), findsNothing);
      expect((await profile.get()).providerOrder, [ruB.id]);
    });

    testWidgets('dragging a provider saves the whole order', (tester) async {
      await pump(tester);
      expect(
        tester.getTopLeft(find.byKey(const Key('order-wiktionary.en-en'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('order-stardict.a'))).dy,
        ),
      );

      final handle = find.descendant(
        of: find.byKey(const Key('order-stardict.b')),
        matching: find.byIcon(Icons.drag_handle),
      );
      await tester.drag(handle, const Offset(0, -400));
      await tester.pumpAndSettle();

      expect((await profile.get()).providerOrder, [
        ruB.id,
        wiktionary.id,
        ruA.id,
      ]);
    });
  });
}
