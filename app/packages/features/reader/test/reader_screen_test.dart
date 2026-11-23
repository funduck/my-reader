import 'dart:async';

import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:features_reader/features_reader.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_api/reader_api.dart';

/// What the fake engines draw; the default is a short text.
Widget Function(BuildContext)? _engineView;

class _FakeChrome implements SystemChromeGateway {
  final List<SystemUiMode> modes = [];

  @override
  Future<void> setMode(SystemUiMode mode) async => modes.add(mode);
}

class _FakeEngine implements ReaderEngine {
  final _events = StreamController<ReaderEvent>.broadcast();
  final List<({OpenedBook book, BookId bookId, Locator? at})> loads = [];
  final List<Locator> goTos = [];
  final List<ReaderSettings> settingsApplied = [];
  final List<List<Locator>> highlights = [];
  bool disposed = false;

  void emit(ReaderEvent event) => _events.add(event);

  @override
  Widget buildView(BuildContext context) =>
      _engineView?.call(context) ?? const Text('engine view');

  @override
  Future<void> load(
    OpenedBook book, {
    required BookId bookId,
    Locator? at,
  }) async => loads.add((book: book, bookId: bookId, at: at));

  @override
  Future<void> goTo(Locator locator) async => goTos.add(locator);

  @override
  void applySettings(ReaderSettings settings) => settingsApplied.add(settings);

  @override
  void highlight(List<Locator> ranges) => highlights.add(ranges);

  @override
  Stream<ReaderEvent> get events => _events.stream;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }
}

final _macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

/// A test on a desktop: the app bar is always shown (without T-087 the old
/// tests run unchanged).
void macTest(String description, Future<void> Function(WidgetTester) body) =>
    testWidgets(description, body, variant: _macOS);

void main() {
  const id = BookId('b1');
  late FakeBookRepository books;
  late FakeProgressRepository progress;
  late FakeProfileRepository profiles;
  late FakeBookFormatAdapter adapter;
  late List<_FakeEngine> engines;
  late _FakeChrome chrome;
  final navigator = GlobalKey<NavigatorState>();
  late List<({String text, Locator at, String sentence})> lookups;

  /// When set, the lookup stays open until it completes.
  Completer<void>? lookupOpen;

  Locator at(int chapter, double progression) => Locator(
    book: id,
    chapter: ChapterRef(href: 'chapter${chapter + 1}.xhtml', index: chapter),
    progression: progression,
  );

  setUp(() async {
    books = FakeBookRepository();
    progress = FakeProgressRepository();
    profiles = FakeProfileRepository();
    adapter = FakeBookFormatAdapter()
      ..register(
        '/x/b1.epub',
        const BookMetadata(title: 'Dune'),
        chapters: ['One.', 'Two.', 'Three.', 'Four.'],
      );
    engines = [];
    chrome = _FakeChrome();
    _engineView = null;
    lookups = [];
    lookupOpen = null;
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

  Widget app({
    Locator? locator,
    BookId bookId = id,
    Key? key,
    void Function(Locator)? onOpenCheatSheet,
    VoidCallback? onOpenHistory,
  }) => ProviderScope(
    overrides: [
      bookRepositoryProvider.overrideWithValue(books),
      progressRepositoryProvider.overrideWithValue(progress),
      profileRepositoryProvider.overrideWithValue(profiles),
      bookFormatsProvider.overrideWithValue([adapter]),
      clockProvider.overrideWithValue(FakeClock()),
      systemChromeProvider.overrideWithValue(chrome),
      lookupPresenterProvider.overrideWithValue((
        context, {
        required text,
        required at,
        required sentence,
      }) async {
        lookups.add((text: text, at: at, sentence: sentence));
        await lookupOpen?.future;
      }),
      readerEngineFactoryProvider.overrideWithValue(() {
        final engine = _FakeEngine();
        engines.add(engine);
        return engine;
      }),
    ],
    child: MaterialApp(
      navigatorKey: navigator,
      home: ReaderScreen(
        key: key,
        bookId: bookId,
        locator: locator,
        onOpenCheatSheet: onOpenCheatSheet,
        onOpenHistory: onOpenHistory,
      ),
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

  group('fullscreen on a phone', () {
    final android = TargetPlatformVariant.only(TargetPlatform.android);
    const tap = ViewTapped(position: Offset.zero, size: Size.zero);

    void phoneTest(
      String description,
      Future<void> Function(WidgetTester) body, {
      TargetPlatformVariant? variant,
    }) => testWidgets(description, body, variant: variant ?? android);

    bool barShown(WidgetTester tester) =>
        tester.getRect(find.byType(AppBar)).bottom > 0;

    Future<void> toggle(WidgetTester tester) async {
      engines.single.emit(tap);
      await tester.pumpAndSettle();
    }

    phoneTest('opens with the app bar hidden and immersive bars', (
      tester,
    ) async {
      await open(tester);
      expect(barShown(tester), isFalse);
      expect(chrome.modes, [SystemUiMode.immersiveSticky]);
      await close(tester);
    });

    phoneTest('ViewTapped shows the bar and the system bars, again hides', (
      tester,
    ) async {
      await open(tester);
      await toggle(tester);
      expect(barShown(tester), isTrue);
      expect(chrome.modes.last, SystemUiMode.edgeToEdge);
      await toggle(tester);
      expect(barShown(tester), isFalse);
      expect(chrome.modes.last, SystemUiMode.immersiveSticky);
      await close(tester);
    });

    phoneTest('starting to scroll hides the menu', (tester) async {
      _engineView = (_) => ListView.builder(
        itemCount: 100,
        itemBuilder: (_, i) => SizedBox(height: 50, child: Text('row $i')),
      );
      await open(tester);
      await toggle(tester);
      expect(barShown(tester), isTrue);
      await tester.drag(find.byType(ListView), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(barShown(tester), isFalse);
      expect(chrome.modes.last, SystemUiMode.immersiveSticky);
      await close(tester);
    });

    phoneTest('going to the history restores the normal bars', (tester) async {
      await tester.pumpWidget(
        app(
          onOpenHistory: () => navigator.currentState!.push(
            MaterialPageRoute<void>(builder: (_) => const Text('history')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await toggle(tester);
      chrome.modes.clear();
      await tester.tap(find.byTooltip('History'));
      await tester.pumpAndSettle();
      expect(find.text('history'), findsOneWidget);
      expect(chrome.modes, [SystemUiMode.edgeToEdge]);

      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(chrome.modes.last, SystemUiMode.edgeToEdge);
      await close(tester);
    });

    phoneTest('closing the screen restores the normal bars', (tester) async {
      await open(tester);
      expect(chrome.modes.last, SystemUiMode.immersiveSticky);
      await close(tester);
      expect(chrome.modes.last, SystemUiMode.edgeToEdge);
    });

    phoneTest('resumed with the menu hidden hides the bars again', (
      tester,
    ) async {
      await open(tester);
      chrome.modes.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(chrome.modes, [SystemUiMode.immersiveSticky]);
      await close(tester);
    });

    phoneTest('resumed with the menu shown leaves the bars', (tester) async {
      await open(tester);
      await toggle(tester);
      chrome.modes.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(chrome.modes, isEmpty);
      await close(tester);
    });

    phoneTest('the reading position does not move with the menu', (
      tester,
    ) async {
      _engineView = (_) => ListView.builder(
        itemCount: 200,
        itemBuilder: (_, i) => SizedBox(height: 50, child: Text('row $i')),
      );
      await open(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      final row = find.text('row 10');
      final before = tester.getTopLeft(row);
      final offset = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .pixels;

      await toggle(tester);
      expect(tester.getTopLeft(row), before);
      await toggle(tester);
      expect(tester.getTopLeft(row), before);
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        offset,
      );
      await close(tester);
    });

    phoneTest('the text keeps the top inset of the cutout in both states', (
      tester,
    ) async {
      tester.view.viewPadding = const FakeViewPadding(top: 30);
      tester.view.padding = FakeViewPadding.zero;
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      final seen = <double>[];
      _engineView = (context) {
        seen.add(MediaQuery.paddingOf(context).top);
        return const Text('engine view');
      };
      await open(tester);
      await toggle(tester);
      await toggle(tester);
      expect(seen, isNotEmpty);
      expect(seen.toSet(), {30.0 / tester.view.devicePixelRatio});
      await close(tester);
    });

    phoneTest('the same on iOS', (tester) async {
      await open(tester);
      expect(barShown(tester), isFalse);
      expect(chrome.modes, [SystemUiMode.immersiveSticky]);
      await close(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    phoneTest('macOS: the bar is always shown and chrome is not touched', (
      tester,
    ) async {
      await open(tester);
      expect(barShown(tester), isTrue);
      await toggle(tester);
      await toggle(tester);
      expect(barShown(tester), isTrue);
      expect(find.text('Dune'), findsOneWidget);
      await close(tester);
      expect(chrome.modes, isEmpty);
    }, variant: _macOS);
  });

  macTest('the warm-up button passes the current position', (tester) async {
    final opened = <Locator>[];
    await tester.pumpWidget(app(onOpenCheatSheet: opened.add));
    await tester.pump();
    await tester.pump();
    // Nothing reported yet: the start of the book.
    await tester.tap(find.byTooltip('Разминка'));
    expect(opened.single.chapter.index, 0);
    expect(opened.single.progression, 0);
    engines.single.emit(PositionChanged(at(2, 0.5)));
    await tester.pump();
    await tester.tap(find.byTooltip('Разминка'));
    expect(opened.last, at(2, 0.5));
    await close(tester);
  });

  macTest('no warm-up button without a callback', (tester) async {
    await open(tester);
    expect(find.byTooltip('Разминка'), findsNothing);
    await close(tester);
  });

  macTest('shows the engine view and the title', (tester) async {
    await open(tester);
    expect(find.text('engine view'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(engines.single.loads.single.at, isNull);
    expect(engines.single.loads.single.bookId, id);
  });

  macTest('saves the position one second after the last change', (
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

  macTest('saves at once when the app is paused', (tester) async {
    await open(tester);
    engines.single.emit(PositionChanged(at(2, 0.5)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(await progress.get(id), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect((await progress.get(id))?.locator, at(2, 0.5));
    await close(tester);
  });

  macTest('saves when the screen is closed and releases the engine', (
    tester,
  ) async {
    await open(tester);
    engines.single.emit(PositionChanged(at(3, 0.1)));
    await tester.pump(const Duration(milliseconds: 100));
    await close(tester);
    expect((await progress.get(id))?.locator, at(3, 0.1));
    expect(engines.single.disposed, isTrue);
  });

  macTest('a new screen resumes from the saved position', (tester) async {
    await open(tester);
    engines.single.emit(PositionChanged(at(2, 0.25)));
    await tester.pump(saveDebounce);
    await close(tester);

    await open(tester);
    expect(engines, hasLength(2));
    expect(engines.last.loads.single.at, at(2, 0.25));
    await close(tester);
  });

  macTest('an explicit locator wins over the saved position', (tester) async {
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

  macTest('the table of contents opens a chapter', (tester) async {
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

  macTest('a selected word is passed to the lookup with place and sentence', (
    tester,
  ) async {
    await open(tester);
    engines.single.emit(
      TextSelected(text: 'sand', at: at(1, 0.25), sentence: 'The sand moves.'),
    );
    await tester.pump();
    expect(lookups, [
      (text: 'sand', at: at(1, 0.25), sentence: 'The sand moves.'),
    ]);
    await close(tester);
  });

  macTest('the selected word is marked while its lookup is open', (
    tester,
  ) async {
    await open(tester);
    final engine = engines.single;
    lookupOpen = Completer<void>();
    engine.emit(
      TextSelected(text: 'sand', at: at(1, 0.25), sentence: 'The sand moves.'),
    );
    await tester.pump();
    expect(engine.highlights, [
      [at(1, 0.25)],
    ]);

    lookupOpen!.complete();
    await tester.pump();
    expect(engine.highlights.last, isEmpty);
    await close(tester);
  });

  macTest('after the lookup the place from history stays marked', (
    tester,
  ) async {
    final target = at(2, 0.5);
    await open(tester, locator: target);
    final engine = engines.single;
    expect(engine.highlights, [
      [target],
    ]);

    lookupOpen = Completer<void>();
    engine.emit(
      TextSelected(text: 'sand', at: at(2, 0.75), sentence: 'The sand moves.'),
    );
    await tester.pump();
    expect(engine.highlights.last, [target, at(2, 0.75)]);

    lookupOpen!.complete();
    await tester.pump();
    expect(engine.highlights.last, [target]);
    await close(tester);
  });

  macTest('a selected phrase is passed to the lookup the same way', (
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

  macTest('a failing lookup does not break the reader', (tester) async {
    // Not wired in this scope: the presenter throws on read.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWithValue(books),
          progressRepositoryProvider.overrideWithValue(progress),
          profileRepositoryProvider.overrideWithValue(profiles),
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
    engines.last.emit(TextSelected(text: 'x', at: at(0, 0), sentence: 'x.'));
    await tester.pump();
    expect(find.text('engine view'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  macTest('an unknown book shows a message', (tester) async {
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

  group('display settings', () {
    macTest('are applied after load and on every profile change', (
      tester,
    ) async {
      await profiles.save(
        const UserProfile(
          display: DisplayPrefs(
            fontSize: 22,
            mode: DisplayMode.night,
            dim: 0.3,
          ),
        ),
      );
      await open(tester);
      final applied = engines.single.settingsApplied;
      expect(applied, isNotEmpty);
      final first = applied.last;
      expect(first.fontSize, 22);
      expect(first.theme, ReaderTheme.dark);
      expect(first.background, const Color(0xFF121212));
      expect(first.text, const Color(0xFFE0E0E0));
      expect(first.dim, 0.3);
      final before = applied.length;
      await profiles.save(
        const UserProfile(display: DisplayPrefs(fontSize: 30)),
      );
      await tester.pump();
      expect(applied.length, before + 1);
      expect(applied.last.fontSize, 30);
      expect(applied.last.theme, ReaderTheme.light);
      await close(tester);
    });

    macTest('the day/night button saves the other mode', (tester) async {
      await open(tester);
      expect(find.byIcon(Icons.light_mode), findsOneWidget);
      await tester.tap(find.byTooltip('Day / Night'));
      await tester.pump();
      await tester.pump();
      expect((await profiles.get()).display.mode, DisplayMode.night);
      expect(engines.single.settingsApplied.last.theme, ReaderTheme.dark);
      expect(find.byIcon(Icons.dark_mode), findsOneWidget);
      await close(tester);
    });

    macTest('a slider saves once after the debounce', (tester) async {
      var saves = 0;
      final counting = _CountingProfiles(profiles, () => saves++);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookRepositoryProvider.overrideWithValue(books),
            progressRepositoryProvider.overrideWithValue(progress),
            profileRepositoryProvider.overrideWithValue(counting),
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
      await tester.tap(find.byTooltip('Text'));
      await tester.pumpAndSettle();
      final slider = find.byKey(const Key('dim'));
      final rect = tester.getRect(slider);
      for (final f in [0.2, 0.4, 0.6]) {
        await tester.tapAt(Offset(rect.left + rect.width * f, rect.center.dy));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(saves, 0);
      expect(engines.single.settingsApplied.last.dim, greaterThan(0));
      await tester.pump(displaySaveDebounce);
      await tester.pump();
      expect(saves, 1);
      expect((await profiles.get()).display.dim, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    macTest('A+ in the panel grows the font by one', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A+'));
      await tester.pump(displaySaveDebounce);
      await tester.pump();
      expect((await profiles.get()).display.fontSize, 19);
      expect(engines.single.settingsApplied.last.fontSize, 19);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}

/// Profile repository that counts saves.
class _CountingProfiles implements ProfileRepository {
  new(this._inner, this._onSave);

  final ProfileRepository _inner;
  final void Function() _onSave;

  @override
  Future<UserProfile> get() => _inner.get();

  @override
  Stream<UserProfile> watch() => _inner.watch();

  @override
  Future<void> save(UserProfile profile) {
    _onSave();
    return _inner.save(profile);
  }
}
