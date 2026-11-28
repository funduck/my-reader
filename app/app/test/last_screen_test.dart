import 'dart:async';

import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:my_reader_app/bootstrap.dart';
import 'package:my_reader_app/last_screen.dart';
import 'package:my_reader_app/router.dart';
import 'package:reader_api/reader_api.dart';
import 'package:text_en/text_en.dart';

class _FakeEngine implements ReaderEngine {
  final _events = StreamController<ReaderEvent>.broadcast();

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

class _OneItemGenerator implements CheatSheetGenerator {
  @override
  Future<CheatSheet> generate({
    required String text,
    required Locator from,
    required Locator to,
    Set<String> knownTerms = const {},
    CancelToken? cancel,
  }) async => CheatSheet(
    from: from,
    to: to,
    items: const [
      CheatSheetItem(
        text: 'spice',
        kind: CheatSheetItemKind.word,
        level: CefrLevel.c1,
      ),
    ],
  );
}

/// What stays on the "device" between two launches of the app.
class _Device {
  final books = FakeBookRepository();
  final profiles = FakeProfileRepository();
  final progress = FakeProgressRepository();
  final adapter = FakeBookFormatAdapter();

  Future<void> addBook(String id, String title) async {
    await books.save(
      Book(
        id: BookId(id),
        metadata: BookMetadata(title: title),
        format: BookFormat.epub,
        filePath: '/x/$id.epub',
        contentHash: id,
        addedAt: DateTime.utc(2024),
      ),
    );
    adapter.register(
      '/x/$id.epub',
      BookMetadata(title: title),
      chapters: ['The spice must flow.'],
    );
  }

  Future<LastScreen?> lastScreen() async => (await profiles.get()).lastScreen;
}

/// B-030 / T-125: after a restart the app opens the reader or the cheat sheet
/// where the user was. A "restart" is a new `ProviderScope` over the same
/// stores.
void main() {
  late _Device device;

  // The menu of the reader is always shown on a desktop; on a phone it hides.
  void desktopTest(
    String name,
    Future<void> Function(WidgetTester tester) body,
  ) => testWidgets(
    name,
    body,
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  setUp(() async {
    device = _Device();
    await device.addBook('b1', 'Dune');
    await device.addBook('b2', 'Emma');
  });

  // The settings screen has an endless spinner (packs) and the cheat sheet
  // loads outside the fake-async zone, so no pumpAndSettle.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  /// Starts the app on [device], as after a launch.
  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(
      bootstrap(
        overrides: [
          ...buildOverrides(),
          textAnalyzerProvider.overrideWithValue(const EnglishTextAnalyzer()),
          lookupProvidersProvider.overrideWithValue(const []),
          dictionaryLibraryProvider.overrideWithValue(_NoDictionaries()),
          bookRepositoryProvider.overrideWithValue(device.books),
          progressRepositoryProvider.overrideWithValue(device.progress),
          profileRepositoryProvider.overrideWithValue(device.profiles),
          bookFormatsProvider.overrideWithValue([device.adapter]),
          lookupJournalProvider.overrideWithValue(FakeLookupJournal()),
          termRepositoryProvider.overrideWithValue(FakeTermRepository()),
          cheatSheetLogProvider.overrideWithValue(FakeCheatSheetLog()),
          cheatSheetGeneratorProvider.overrideWithValue(_OneItemGenerator()),
          readerEngineFactoryProvider.overrideWithValue(_FakeEngine.new),
        ],
      ),
    );
    await settle(tester);
  }

  /// Closes the app and starts it again over the same stores.
  Future<void> restart(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    await launch(tester);
  }

  GoRouter routerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
          .read(routerProvider);

  Future<void> tapButton(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await settle(tester);
  }

  // The reader has a drawer instead of a back button: use the system back.
  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await settle(tester);
  }

  final library = find.widgetWithText(AppBar, 'Library');
  Finder appBar(String title) => find.widgetWithText(AppBar, title);

  const reader1 = LastScreen(kind: LastScreenKind.reader, book: BookId('b1'));
  const sheet1 = LastScreen(
    kind: LastScreenKind.cheatsheet,
    book: BookId('b1'),
  );

  desktopTest('a fresh install starts on the library', (tester) async {
    await launch(tester);
    expect(library, findsOneWidget);
    expect(await device.lastScreen(), isNull);
  });

  desktopTest('reader: restart opens the book, back goes to the library', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(find.text('Dune'));
    await settle(tester);
    expect(appBar('Dune'), findsOneWidget);
    expect(await device.lastScreen(), reader1);

    await restart(tester);
    expect(appBar('Dune'), findsOneWidget);
    expect(find.text('engine view'), findsOneWidget);
    expect(await device.lastScreen(), reader1);

    await back(tester);
    expect(library, findsOneWidget);
  });

  desktopTest('cheat sheet: restart opens it over the book, back goes to '
      'the book, then to the library', (tester) async {
    await launch(tester);
    unawaited(routerOf(tester).push<void>(Routes.cheatsheetFor('b1')));
    await settle(tester);
    expect(find.text('spice'), findsOneWidget);
    expect(await device.lastScreen(), sheet1);

    await restart(tester);
    expect(find.text('spice'), findsOneWidget);
    expect(find.text('Читать'), findsOneWidget);
    expect(await device.lastScreen(), sheet1);

    await back(tester);
    expect(appBar('Dune'), findsOneWidget);
    expect(await device.lastScreen(), reader1);
    await back(tester);
    expect(library, findsOneWidget);
  });

  desktopTest('cheat sheet: "Читать" after a restart opens the reader, back '
      'goes to the library', (tester) async {
    await launch(tester);
    unawaited(routerOf(tester).push<void>(Routes.cheatsheetFor('b1')));
    await settle(tester);
    await restart(tester);

    await tester.tap(find.text('Читать'));
    await settle(tester);
    expect(appBar('Dune'), findsOneWidget);
    expect(await device.lastScreen(), reader1);
    await back(tester);
    expect(library, findsOneWidget);
  });

  desktopTest('reader -> cheat sheet -> reader keeps the book', (tester) async {
    await launch(tester);
    await tester.tap(find.text('Dune'));
    await settle(tester);
    await tapButton(tester, 'Разминка');
    await settle(tester);
    expect(await device.lastScreen(), sheet1);
    await tester.tap(find.text('Читать'));
    await settle(tester);
    expect(await device.lastScreen(), reader1);
  });

  for (final (name, tooltip, title) in [
    ('history', 'History', 'History'),
    ('settings', 'Settings', 'Settings'),
  ]) {
    desktopTest('from $name a restart opens the book the user came from', (
      tester,
    ) async {
      await launch(tester);
      await tester.tap(find.text('Dune'));
      await settle(tester);
      await tapButton(tester, tooltip);
      expect(appBar(title), findsOneWidget);
      expect(await device.lastScreen(), reader1);

      await restart(tester);
      expect(appBar('Dune'), findsOneWidget);
      expect(find.text('engine view'), findsOneWidget);
      await back(tester);
      expect(library, findsOneWidget);
    });
  }

  desktopTest('from the cheat sheet to settings: a restart opens the sheet', (
    tester,
  ) async {
    await launch(tester);
    unawaited(routerOf(tester).push<void>(Routes.cheatsheetFor('b2')));
    await settle(tester);
    unawaited(routerOf(tester).push<void>(Routes.settings));
    await settle(tester);
    expect(appBar('Settings'), findsOneWidget);

    await restart(tester);
    expect(find.text('spice'), findsOneWidget);
    expect(
      await device.lastScreen(),
      const LastScreen(kind: LastScreenKind.cheatsheet, book: BookId('b2')),
    );
  });

  desktopTest('history, settings alone do not store anything', (tester) async {
    await launch(tester);
    await tapButton(tester, 'History');
    await back(tester);
    await tapButton(tester, 'Settings');
    expect(await device.lastScreen(), isNull);
    await restart(tester);
    expect(library, findsOneWidget);
  });

  desktopTest('back to the library erases the record', (tester) async {
    await launch(tester);
    await tester.tap(find.text('Dune'));
    await settle(tester);
    expect(await device.lastScreen(), reader1);
    await back(tester);
    expect(library, findsOneWidget);
    expect(await device.lastScreen(), isNull);

    await restart(tester);
    expect(library, findsOneWidget);
  });

  desktopTest('the other book replaces the record', (tester) async {
    await launch(tester);
    await tester.tap(find.text('Dune'));
    await settle(tester);
    await back(tester);
    await tester.tap(find.text('Emma'));
    await settle(tester);

    await restart(tester);
    expect(appBar('Emma'), findsOneWidget);
  });

  desktopTest('a deleted book: the library, and the record is erased', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(find.text('Dune'));
    await settle(tester);
    expect(await device.lastScreen(), reader1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    await device.books.remove(const BookId('b1'));

    await launch(tester);
    expect(library, findsOneWidget);
    expect(await device.lastScreen(), isNull);
    await restart(tester);
    expect(library, findsOneWidget);
  });

  desktopTest('a record that does not parse is the library', (tester) async {
    await device.profiles.save(
      UserProfile.fromJson(const {
        'lastScreen': {'kind': 'history', 'book': 'b1'},
      }),
    );
    await launch(tester);
    expect(library, findsOneWidget);
  });

  desktopTest('a stored profile without the field opens the library', (
    tester,
  ) async {
    await device.profiles.save(UserProfile.fromJson(const {'level': 'c1'}));
    await launch(tester);
    expect(library, findsOneWidget);
    expect((await device.profiles.get()).level, CefrLevel.c1);
  });

  test('lastScreenOf maps paths to records', () {
    expect(lastScreenOf('/library'), (defined: true, screen: null));
    expect(lastScreenOf('/'), (defined: true, screen: null));
    expect(lastScreenOf('/reader/b1?locator=%7B%7D'), (
      defined: true,
      screen: reader1,
    ));
    expect(lastScreenOf('/cheatsheet/b1'), (defined: true, screen: sheet1));
    expect(lastScreenOf('/history'), (defined: false, screen: null));
    expect(lastScreenOf('/settings'), (defined: false, screen: null));
    expect(lastScreenOf('/reader'), (defined: false, screen: null));
  });
}
