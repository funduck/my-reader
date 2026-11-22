import 'dart:async';

import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:features_reader/features_reader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_api/reader_api.dart';

class _FakeEngine implements ReaderEngine {
  final _events = StreamController<ReaderEvent>.broadcast();
  final List<({OpenedBook book, BookId bookId, Locator? at})> loads = [];
  final List<Locator> goTos = [];
  bool disposed = false;

  void emit(ReaderEvent event) => _events.add(event);

  @override
  Widget buildView(BuildContext context) => const Text('engine view');

  @override
  Future<void> load(
    OpenedBook book, {
    required BookId bookId,
    Locator? at,
  }) async => loads.add((book: book, bookId: bookId, at: at));

  @override
  Future<void> goTo(Locator locator) async => goTos.add(locator);

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
  late FakeBookRepository books;
  late FakeProgressRepository progress;
  late FakeBookFormatAdapter adapter;
  late List<_FakeEngine> engines;
  late List<({String text, Locator at, String sentence})> lookups;

  Locator at(int chapter, double progression) => Locator(
    book: id,
    chapter: ChapterRef(href: 'chapter${chapter + 1}.xhtml', index: chapter),
    progression: progression,
  );

  setUp(() async {
    books = FakeBookRepository();
    progress = FakeProgressRepository();
    adapter = FakeBookFormatAdapter()
      ..register(
        '/x/b1.epub',
        const BookMetadata(title: 'Dune'),
        chapters: ['One.', 'Two.', 'Three.', 'Four.'],
      );
    engines = [];
    lookups = [];
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

  Widget app({Locator? locator, BookId bookId = id, Key? key}) => ProviderScope(
    overrides: [
      bookRepositoryProvider.overrideWithValue(books),
      progressRepositoryProvider.overrideWithValue(progress),
      bookFormatsProvider.overrideWithValue([adapter]),
      clockProvider.overrideWithValue(FakeClock()),
      lookupPresenterProvider.overrideWithValue(
        (context, {required text, required at, required sentence}) async =>
            lookups.add((text: text, at: at, sentence: sentence)),
      ),
      readerEngineFactoryProvider.overrideWithValue(() {
        final engine = _FakeEngine();
        engines.add(engine);
        return engine;
      }),
    ],
    child: MaterialApp(
      home: ReaderScreen(key: key, bookId: bookId, locator: locator),
    ),
  );

  Future<void> open(WidgetTester tester, {Locator? locator}) async {
    await tester.pumpWidget(app(locator: locator));
    await tester.pump();
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('shows the engine view and the title', (tester) async {
    await open(tester);
    expect(find.text('engine view'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(engines.single.loads.single.at, isNull);
    expect(engines.single.loads.single.bookId, id);
  });

  testWidgets('saves the position one second after the last change', (
    tester,
  ) async {
    await open(tester);
    engines.single.emit(PositionChanged(at(1, 0.2)));
    await tester.pump(const Duration(milliseconds: 600));
    // A newer position restarts the countdown.
    engines.single.emit(PositionChanged(at(1, 0.4)));
    await tester.pump(const Duration(milliseconds: 999));
    expect(await progress.get(id), isNull);
    await tester.pump(const Duration(milliseconds: 1));
    final saved = await progress.get(id);
    expect(saved?.locator, at(1, 0.4));
    expect(saved?.percent, closeTo(0.35, 1e-9));
    await close(tester);
  });

  testWidgets('saves at once when the app is paused', (tester) async {
    await open(tester);
    engines.single.emit(PositionChanged(at(2, 0.5)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(await progress.get(id), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect((await progress.get(id))?.locator, at(2, 0.5));
    await close(tester);
  });

  testWidgets('saves when the screen is closed and releases the engine', (
    tester,
  ) async {
    await open(tester);
    engines.single.emit(PositionChanged(at(3, 0.1)));
    await tester.pump(const Duration(milliseconds: 100));
    await close(tester);
    expect((await progress.get(id))?.locator, at(3, 0.1));
    expect(engines.single.disposed, isTrue);
  });

  testWidgets('a new screen resumes from the saved position', (tester) async {
    await open(tester);
    engines.single.emit(PositionChanged(at(2, 0.25)));
    await tester.pump(saveDebounce);
    await close(tester);

    await open(tester);
    expect(engines, hasLength(2));
    expect(engines.last.loads.single.at, at(2, 0.25));
    await close(tester);
  });

  testWidgets('an explicit locator wins over the saved position', (
    tester,
  ) async {
    await progress.save(
      ReadingProgress(
        locator: at(0, 0.9),
        percent: 0.2,
        updatedAt: DateTime.utc(2024),
      ),
    );
    await open(tester, locator: at(3, 0.5));
    expect(engines.single.loads.single.at, at(3, 0.5));
    await close(tester);
  });

  testWidgets('the table of contents opens a chapter', (tester) async {
    await open(tester);
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    expect(find.text('Chapter 3'), findsOneWidget);
    await tester.tap(find.text('Chapter 3'));
    await tester.pumpAndSettle();
    expect(engines.single.goTos.single.chapter.index, 2);
    expect(engines.single.goTos.single.book, id);
    expect(find.text('Chapter 3'), findsNothing);
    await close(tester);
  });

  testWidgets('a tapped word is passed to the lookup with place and sentence', (
    tester,
  ) async {
    await open(tester);
    engines.single.emit(
      WordTapped(word: 'sand', at: at(1, 0.25), sentence: 'The sand moves.'),
    );
    await tester.pump();
    expect(lookups, [
      (text: 'sand', at: at(1, 0.25), sentence: 'The sand moves.'),
    ]);
    await close(tester);
  });

  testWidgets('a selection is passed to the lookup the same way', (
    tester,
  ) async {
    await open(tester);
    engines.single.emit(
      TextSelected(
        text: 'sand moves',
        at: at(2, 0.5),
        sentence: 'The sand moves.',
      ),
    );
    await tester.pump();
    expect(lookups, [
      (text: 'sand moves', at: at(2, 0.5), sentence: 'The sand moves.'),
    ]);
    await close(tester);
  });

  testWidgets('a failing lookup does not break the reader', (tester) async {
    // Not wired in this scope: the presenter throws on read.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWithValue(books),
          progressRepositoryProvider.overrideWithValue(progress),
          bookFormatsProvider.overrideWithValue([adapter]),
          clockProvider.overrideWithValue(FakeClock()),
          readerEngineFactoryProvider.overrideWithValue(() {
            final engine = _FakeEngine();
            engines.add(engine);
            return engine;
          }),
        ],
        child: const MaterialApp(home: ReaderScreen(bookId: id)),
      ),
    );
    await tester.pump();
    await tester.pump();
    engines.last.emit(WordTapped(word: 'x', at: at(0, 0), sentence: 'x.'));
    await tester.pump();
    expect(find.text('engine view'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('an unknown book shows a message', (tester) async {
    await tester.pumpWidget(app(bookId: const BookId('nope')));
    await tester.pump();
    await tester.pump();
    expect(find.text('This book is not in the library.'), findsOneWidget);
    expect(engines, isEmpty);
  });

  group('locator parameter', () {
    test('round trip', () {
      final locator = at(1, 0.5);
      expect(parseLocatorParam(encodeLocatorParam(locator)), locator);
    });

    test('missing or malformed gives null', () {
      expect(parseLocatorParam(null), isNull);
      expect(parseLocatorParam(''), isNull);
      expect(parseLocatorParam('{"a":1}'), isNull);
      expect(parseLocatorParam('[1]'), isNull);
      expect(parseLocatorParam('not json'), isNull);
    });
  });
}
