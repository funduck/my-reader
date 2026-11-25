import 'dart:async';
import 'dart:io';

import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:my_reader_app/bootstrap.dart';
import 'package:my_reader_app/router.dart';
import 'package:reader_api/reader_api.dart';

class _FakeEngine implements ReaderEngine {
  final _events = StreamController<ReaderEvent>.broadcast();

  void emit(ReaderEvent event) => _events.add(event);

  @override
  Widget buildView(BuildContext context) => const Text('engine view');

  @override
  Future<void> load(
    OpenedBook book, {
    required BookId bookId,
    Locator? at,
  }) async {}

  @override
  Future<void> goTo(Locator locator) async {}

  @override
  void applySettings(ReaderSettings settings) {}

  @override
  void highlight(ReaderHighlights highlights) {}

  @override
  Stream<ReaderEvent> get events => _events.stream;

  @override
  Future<void> dispose() => _events.close();
}

class _NoDictionaries implements DictionaryLibrary {
  @override
  Future<List<ImportedDictionary>> list() async => const [];

  @override
  Future<ImportedDictionary> import(List<String> files, LookupMode mode) =>
      throw UnimplementedError();

  @override
  Future<bool> remove(String id) async => false;
}

/// Settings and history are reachable from the library and the reader, and
/// "Back" returns to where the user came from.
void main() {
  const id = BookId('b1');
  late _FakeEngine engine;

  Future<void> pumpApp(WidgetTester tester, {String? at}) async {
    engine = _FakeEngine();
    final books = FakeBookRepository();
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
    final adapter = FakeBookFormatAdapter()
      ..register(
        '/x/b1.epub',
        const BookMetadata(title: 'Dune'),
        chapters: ['One.'],
      );
    // No packs and no providers: the sheet shows "No dictionary available".
    final noPacks = '${Directory.systemTemp.path}/my-reader-no-packs';
    await tester.pumpWidget(
      bootstrap(
        overrides: [
          ...buildOverrides(),
          ...buildLookupOverrides(noPacks, providers: (_) => []),
          dictionaryLibraryProvider.overrideWithValue(_NoDictionaries()),
          bookRepositoryProvider.overrideWithValue(books),
          progressRepositoryProvider.overrideWithValue(
            FakeProgressRepository(),
          ),
          profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
          bookFormatsProvider.overrideWithValue([adapter]),
          lookupJournalProvider.overrideWithValue(FakeLookupJournal()),
          termRepositoryProvider.overrideWithValue(FakeTermRepository()),
          cheatSheetLogProvider.overrideWithValue(FakeCheatSheetLog()),
          readerEngineFactoryProvider.overrideWithValue(() => engine),
          if (at != null)
            routerProvider.overrideWith(
              (ref) => createRouter(initialLocation: at),
            ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  // The settings screen has an endless spinner (packs), so no pumpAndSettle.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tapButton(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await settle(tester);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton));
    await settle(tester);
  }

  testWidgets('library -> settings -> back -> library', (tester) async {
    await pumpApp(tester);
    await tapButton(tester, 'Settings');
    expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
    await back(tester);
    expect(find.widgetWithText(AppBar, 'Library'), findsOneWidget);
  });

  testWidgets('library -> history -> back -> library', (tester) async {
    await pumpApp(tester);
    await tapButton(tester, 'History');
    expect(find.widgetWithText(AppBar, 'History'), findsOneWidget);
    await back(tester);
    expect(find.widgetWithText(AppBar, 'Library'), findsOneWidget);
  });

  testWidgets('reader -> settings -> back -> the same book', (tester) async {
    await pumpApp(tester, at: Routes.readerAt('b1'));
    expect(find.widgetWithText(AppBar, 'Dune'), findsOneWidget);
    await tapButton(tester, 'Settings');
    expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
    await back(tester);
    expect(find.widgetWithText(AppBar, 'Dune'), findsOneWidget);
    expect(find.text('engine view'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('reader -> history -> back -> the same book', (tester) async {
    await pumpApp(tester, at: Routes.readerAt('b1'));
    await tapButton(tester, 'History');
    expect(find.widgetWithText(AppBar, 'History'), findsOneWidget);
    await back(tester);
    expect(find.widgetWithText(AppBar, 'Dune'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('word sheet -> settings -> back -> reader', (tester) async {
    await pumpApp(tester, at: Routes.readerAt('b1'));
    engine.emit(
      const TextSelected(
        text: 'sand',
        at: Locator(
          book: id,
          chapter: ChapterRef(href: 'chapter1.xhtml', index: 0),
          progression: 0.25,
        ),
        sentence: 'The sand moves.',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open settings'));
    await settle(tester);
    expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
    await back(tester);
    expect(find.widgetWithText(AppBar, 'Dune'), findsOneWidget);
    expect(find.text('engine view'), findsOneWidget);
  });
}
