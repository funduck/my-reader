import 'dart:async';

import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:features_reader/features_reader.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_reader_app/bootstrap.dart';
import 'package:my_reader_app/router.dart';
import 'package:reader_api/reader_api.dart';
import 'package:storage_drift/storage_drift.dart';

class _FakeEngine implements ReaderEngine {
  final _events = StreamController<ReaderEvent>.broadcast();
  final List<Locator?> loadedAt = [];
  bool disposed = false;

  void emit(ReaderEvent event) => _events.add(event);

  @override
  Widget buildView(BuildContext context) => const Text('engine view');

  @override
  Future<void> load(
    OpenedBook book, {
    required BookId bookId,
    Locator? at,
  }) async => loadedAt.add(at);

  @override
  Future<void> goTo(Locator locator) async {}

  @override
  void applySettings(ReaderSettings settings) {}

  @override
  void highlight(List<Locator> ranges) {}

  @override
  Stream<ReaderEvent> get events => _events.stream;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }
}

void main() {
  const id = BookId('b1');
  late AppDatabase database;
  late List<_FakeEngine> engines;

  Locator at(int chapter, double progression) => Locator(
    book: id,
    chapter: ChapterRef(href: 'chapter${chapter + 1}.xhtml', index: chapter),
    progression: progression,
  );

  setUp(() async {
    engines = [];
    database = openInMemory();
    final adapter = FakeBookFormatAdapter()
      ..register(
        '/x/b1.epub',
        const BookMetadata(title: 'Dune'),
        chapters: ['One.', 'Two.', 'Three.', 'Four.'],
      );
    await database.bookRepository.save(
      Book(
        id: id,
        metadata: const BookMetadata(title: 'Dune'),
        format: BookFormat.epub,
        filePath: '/x/b1.epub',
        contentHash: 'h',
        addedAt: DateTime.utc(2024),
      ),
    );
    addTearDown(database.close);
    _adapter = adapter;
  });

  Future<void> pumpAt(WidgetTester tester, String location) async {
    await tester.pumpWidget(
      bootstrap(
        overrides: [
          ...buildOverrides(),
          bookRepositoryProvider.overrideWithValue(database.bookRepository),
          progressRepositoryProvider.overrideWithValue(
            database.progressRepository,
          ),
          bookFormatsProvider.overrideWithValue([_adapter]),
          readerEngineFactoryProvider.overrideWithValue(() {
            final engine = _FakeEngine();
            engines.add(engine);
            return engine;
          }),
          routerProvider.overrideWith(
            (ref) => createRouter(initialLocation: location),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  GoRouter routerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Text).first))
          .read(routerProvider);

  Future<ReadingProgress?> saved(WidgetTester tester) => tester
      .runAsync(() => database.progressRepository.get(id))
      .then((value) => value);

  testWidgets('the route opens the book in the engine', (tester) async {
    await pumpAt(tester, Routes.readerAt('b1'));
    expect(find.text('engine view'), findsOneWidget);
    expect(engines.single.loadedAt, [null]);
  });

  testWidgets('the locator parameter opens the book at that place', (
    tester,
  ) async {
    final locator = at(2, 0.5);
    await pumpAt(
      tester,
      Routes.readerAt('b1', locator: encodeLocatorParam(locator)),
    );
    expect(engines.single.loadedAt, [locator]);
  });

  testWidgets('a malformed locator parameter falls back to the saved place', (
    tester,
  ) async {
    await tester.runAsync(
      () => database.progressRepository.save(
        ReadingProgress(
          locator: at(1, 0.3),
          percent: 0.3,
          updatedAt: DateTime.utc(2024),
        ),
      ),
    );
    await pumpAt(tester, Routes.readerAt('b1', locator: '{"a":1}'));
    expect(engines.single.loadedAt, [at(1, 0.3)]);
  });

  testWidgets('position is saved on pause and on close, then restored', (
    tester,
  ) async {
    await pumpAt(tester, Routes.readerAt('b1'));
    final router = routerOf(tester);

    engines.single.emit(PositionChanged(at(1, 0.5)));
    await tester.pump(const Duration(milliseconds: 100));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect((await saved(tester))?.locator, at(1, 0.5));
    // Frames are off while the app is paused.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    engines.single.emit(PositionChanged(at(2, 0.25)));
    await tester.pump(const Duration(milliseconds: 100));
    router.go(Routes.cheatsheetFor('b1'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect((await saved(tester))?.locator, at(2, 0.25));
    expect(engines.single.disposed, isTrue);

    router.go(Routes.readerAt('b1'));
    await tester.pumpAndSettle();
    expect(engines, hasLength(2));
    expect(engines.last.loadedAt, [at(2, 0.25)]);
  });
}

late BookFormatAdapter _adapter;
