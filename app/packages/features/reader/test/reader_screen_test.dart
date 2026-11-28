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
  final List<ReaderHighlights> allHighlights = [];
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
  void highlight(ReaderHighlights highlights) {
    allHighlights.add(highlights);
    this.highlights.add(highlights.ranges[HighlightKind.focus] ?? const []);
  }

  @override
  Stream<ReaderEvent> get events => _events.stream;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }
}

/// A generator that finds the same candidates in every chapter: a word each
/// of A2, C1 and C2, with frequencies, one without a level and one proper
/// name. Records the texts it was given.
class _FakeGenerator implements CheatSheetGenerator {
  final List<String> texts = [];

  @override
  Future<CheatSheet> generate({
    required String text,
    required Locator from,
    required Locator to,
    Set<String> knownTerms = const {},
    CancelToken? cancel,
  }) async {
    texts.add(text);
    CheatSheetItem item(String word, CefrLevel level, double zipf) =>
        CheatSheetItem(
          text: word,
          kind: CheatSheetItemKind.word,
          level: level,
          zipf: zipf,
        );
    return CheatSheet(
      from: from,
      to: to,
      items: [
        item('apple', CefrLevel.a2, 6),
        item('cargo', CefrLevel.c1, 5),
        item('dusk', CefrLevel.c2, 2),
        const CheatSheetItem(text: 'mystery', kind: CheatSheetItemKind.word),
        const CheatSheetItem(
          text: 'london',
          kind: CheatSheetItemKind.word,
          level: CefrLevel.c1,
          zipf: 3,
          isProperName: true,
        ),
        if (text == 'Two.') item('ember', CefrLevel.c1, 4),
      ],
    );
  }
}

class _WordAnalyzer implements TextAnalyzer {
  @override
  List<SentenceSpan> sentences(String text) => [SentenceSpan(0, text.length)];

  @override
  List<TextToken> tokens(String text) => [
    for (final m in RegExp('[A-Za-z]+').allMatches(text))
      TextToken(m[0]!, m.start, m.end),
  ];

  /// `running` -> `run`, so that a form maps to its lemma.
  @override
  String lemma(String word) {
    final w = word.toLowerCase();
    return w == 'running' ? 'run' : w;
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
  late _FakeGenerator generator;
  late FakeBookFormatAdapter adapter;
  late List<_FakeEngine> engines;
  late _FakeChrome chrome;
  late FakeCheatSheetLog cheatSheets;
  late FakeLookupJournal journal;
  late FakeTermRepository terms;
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
    terms = FakeTermRepository();
    generator = _FakeGenerator();
    adapter = FakeBookFormatAdapter()
      ..register(
        '/x/b1.epub',
        const BookMetadata(title: 'Dune'),
        chapters: ['One.', 'Two.', 'Three.', 'Four.'],
      );
    engines = [];
    chrome = _FakeChrome();
    cheatSheets = FakeCheatSheetLog();
    journal = FakeLookupJournal();
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
      cheatSheetLogProvider.overrideWithValue(cheatSheets),
      lookupJournalProvider.overrideWithValue(journal),
      termRepositoryProvider.overrideWithValue(terms),
      textAnalyzerProvider.overrideWithValue(_WordAnalyzer()),
      cheatSheetGeneratorProvider.overrideWithValue(generator),
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

    bool panelShown(WidgetTester tester) =>
        tester.getRect(find.byType(LinearProgressIndicator)).top <
        tester.view.physicalSize.height / tester.view.devicePixelRatio;

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

    phoneTest('the progress panel is shown and hidden with the menu', (
      tester,
    ) async {
      await open(tester);
      final viewTop = tester.getTopLeft(find.text('engine view'));
      expect(panelShown(tester), isFalse);
      await toggle(tester);
      expect(panelShown(tester), isTrue);
      expect(find.text('Chapter 1 · 0%'), findsOneWidget);
      // It lies over the text: the text stays where it was.
      expect(tester.getTopLeft(find.text('engine view')), viewTop);
      await toggle(tester);
      expect(panelShown(tester), isFalse);
      expect(barShown(tester), isFalse);
      await close(tester);
    });

    phoneTest('the progress panel keeps above the system bottom inset', (
      tester,
    ) async {
      tester.view.padding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.resetPadding);
      await open(tester);
      await toggle(tester);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final bar = tester.getRect(find.byType(LinearProgressIndicator));
      // 48 physical pixels of the inset and 8 of the panel's own padding.
      final inset = 48 / tester.view.devicePixelRatio;
      expect(bar.bottom, closeTo(screen.height - inset - 8, 0.01));
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

  group('progress panel', () {
    // Chapters of 4, 4, 6 and 5 characters: 19 in all.
    String caption(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(
            of: find
                .ancestor(
                  of: find.byType(LinearProgressIndicator),
                  matching: find.byType(Column),
                )
                .first,
            matching: find.byType(Text),
          ),
        )
        .data!;

    macTest('shows the chapter and the percent after PositionChanged', (
      tester,
    ) async {
      await open(tester);
      engines.single.emit(PositionChanged(at(2, 0.5)));
      await tester.pump();
      await tester.pump();
      // (4 + 4 + 0.5 * 6) / 19 = 57.9 %
      expect(find.text('Chapter 3 · 58%'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(11 / 19, 1e-9));

      engines.single.emit(PositionChanged(at(3, 1)));
      await tester.pump();
      await tester.pump();
      expect(find.text('Chapter 4 · 100%'), findsOneWidget);
      await close(tester);
    });

    macTest('starts at the place where the book opened', (tester) async {
      await open(tester, locator: at(1, 0));
      expect(find.text('Chapter 2 · 21%'), findsOneWidget);
      await close(tester);
    });

    macTest('without a table of contents entry shows only the percent', (
      tester,
    ) async {
      adapter = _WrappedAdapter(noToc: true)
        ..register(
          '/x/b1.epub',
          const BookMetadata(title: 'Dune'),
          chapters: ['One.', 'Two.', 'Three.', 'Four.'],
        );
      await open(tester);
      engines.single.emit(PositionChanged(at(2, 0.5)));
      await tester.pump();
      await tester.pump();
      expect(caption(tester), '58%');
      await close(tester);
    });

    macTest('before the chapters are measured chapters weigh the same', (
      tester,
    ) async {
      final gate = Completer<void>();
      adapter = _WrappedAdapter(gate: gate.future)
        ..register(
          '/x/b1.epub',
          const BookMetadata(title: 'Dune'),
          chapters: ['One.', 'Two.', 'Three.', 'Four.'],
        );
      await open(tester);
      engines.single.emit(PositionChanged(at(1, 0.5)));
      await tester.pump();
      await tester.pump();
      expect(caption(tester), 'Chapter 2 · 38%');

      gate.complete();
      await tester.pump();
      await tester.pump();
      // (4 + 0.5 * 4) / 19 = 31.6 %
      expect(caption(tester), 'Chapter 2 · 32%');
      await close(tester);
    });

    macTest('closing the screen while measuring stops without an error', (
      tester,
    ) async {
      final gate = Completer<void>();
      adapter = _WrappedAdapter(gate: gate.future)
        ..register(
          '/x/b1.epub',
          const BookMetadata(title: 'Dune'),
          chapters: ['One.', 'Two.', 'Three.', 'Four.'],
        );
      await open(tester);
      await close(tester);
      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
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
    // Chapters of 4, 4, 6 and 5 characters: (4 + 0.4 * 4) / 19.
    expect(saved?.percent, closeTo(5.6 / 19, 1e-9));
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

  group('current chapter in the table of contents', () {
    Future<void> openToc(WidgetTester tester) async {
      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();
    }

    ListTile tile(WidgetTester tester, String title) => tester.widget<ListTile>(
      find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
    );

    macTest('is selected and bold after a position change', (tester) async {
      await open(tester);
      engines.single.emit(PositionChanged(at(2, 0.5)));
      await tester.pump();
      await openToc(tester);
      expect(tile(tester, 'Chapter 3').selected, isTrue);
      final style = tester.widget<Text>(find.text('Chapter 3')).style;
      expect(style?.fontWeight, FontWeight.bold);
      expect(tile(tester, 'Chapter 2').selected, isFalse);
      expect(tester.widget<Text>(find.text('Chapter 2')).style, isNull);
      await close(tester);
    });

    macTest('follows the position between openings', (tester) async {
      await open(tester);
      engines.single.emit(PositionChanged(at(1, 0.1)));
      await tester.pump();
      await openToc(tester);
      expect(tile(tester, 'Chapter 2').selected, isTrue);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      engines.single.emit(PositionChanged(at(3, 0.1)));
      await tester.pump();
      await openToc(tester);
      expect(tile(tester, 'Chapter 4').selected, isTrue);
      expect(tile(tester, 'Chapter 2').selected, isFalse);
      await close(tester);
    });

    macTest('nothing is selected before the first position', (tester) async {
      await open(tester);
      await openToc(tester);
      for (final title in ['Chapter 1', 'Chapter 2', 'Chapter 3']) {
        expect(tile(tester, title).selected, isFalse);
      }
      await close(tester);
    });

    macTest('is scrolled into view in a long table of contents', (
      tester,
    ) async {
      adapter.register(
        '/x/b1.epub',
        const BookMetadata(title: 'Dune'),
        chapters: [for (var i = 0; i < 60; i++) 'Text $i.'],
      );
      await open(tester);
      engines.single.emit(PositionChanged(at(50, 0.5)));
      await tester.pump();
      await openToc(tester);
      final finder = find.text('Chapter 51');
      expect(finder, findsOneWidget);
      expect(tile(tester, 'Chapter 51').selected, isTrue);
      final drawer = tester.getRect(find.byType(Drawer));
      expect(drawer.contains(tester.getCenter(finder)), isTrue);
      final first = tester.getCenter(find.text('Chapter 1'));
      expect(drawer.contains(first), isFalse);
      await close(tester);
    });
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

  group('word highlights (T-119)', () {
    final shownAt = DateTime.utc(2024, 5, 1, 12);
    var eventNo = 0;

    LookupEvent event(String text, DateTime when) => LookupEvent(
      id: LookupEventId('e${eventNo++}'),
      query: LookupQuery(text: text, mode: LookupMode.enEn, locator: at(0, 0)),
      result: const LookupResult(provider: ProviderId('p'), senses: []),
      at: when,
    );

    Set<String> words(_FakeEngine e, HighlightKind kind) =>
        e.allHighlights.isEmpty
        ? const {}
        : e.allHighlights.last.words[kind] ?? const {};

    Future<void> saveSheet(List<String> lemmas, {DateTime? when}) =>
        cheatSheets.save(
          CheatSheetSnapshot(
            book: id,
            shownAt: when ?? shownAt,
            lemmas: lemmas,
          ),
        );

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
    }

    macTest('the words of the last cheat sheet are cheatSheet', (tester) async {
      await saveSheet(['Dune', 'sand', 'take off']);
      await open(tester);
      final engine = engines.single;
      // A phrase is not a lemma; the rest is lower case.
      expect(words(engine, HighlightKind.cheatSheet), {'dune', 'sand'});
      expect(words(engine, HighlightKind.lookedUp), isEmpty);
      await close(tester);
    });

    macTest('a lookup after the cheat sheet is lookedUp, one before is not', (
      tester,
    ) async {
      await saveSheet(['sand']);
      await journal.record(
        event('spice', shownAt.subtract(const Duration(minutes: 1))),
      );
      await journal.record(
        event('running', shownAt.add(const Duration(minutes: 1))),
      );
      await journal.record(
        event('take off', shownAt.add(const Duration(minutes: 2))),
      );
      await open(tester);
      final engine = engines.single;
      // By the lemma of the term; a phrase is left out.
      expect(words(engine, HighlightKind.lookedUp), {'run'});
      expect(words(engine, HighlightKind.cheatSheet), {'sand'});
      await close(tester);
    });

    macTest('without a cheat sheet every lookup of the book counts', (
      tester,
    ) async {
      await journal.record(event('spice', DateTime.utc(2020)));
      await open(tester);
      expect(words(engines.single, HighlightKind.lookedUp), {'spice'});
      await close(tester);
    });

    macTest('a lookup of another book does not count', (tester) async {
      await journal.record(
        LookupEvent(
          id: const LookupEventId('other'),
          query: const LookupQuery(
            text: 'water',
            mode: LookupMode.enEn,
            locator: Locator(
              book: BookId('b2'),
              chapter: ChapterRef(href: 'c.xhtml', index: 0),
              progression: 0,
            ),
          ),
          result: const LookupResult(provider: ProviderId('p'), senses: []),
          at: shownAt,
        ),
      );
      await open(tester);
      expect(words(engines.single, HighlightKind.lookedUp), isEmpty);
      await close(tester);
    });

    macTest('a new lookup is marked at once', (tester) async {
      await open(tester);
      final engine = engines.single;
      expect(words(engine, HighlightKind.lookedUp), isEmpty);
      await journal.record(event('water', shownAt));
      await settle(tester);
      expect(words(engine, HighlightKind.lookedUp), {'water'});
      await close(tester);
    });

    macTest('a new cheat sheet resets lookedUp', (tester) async {
      await saveSheet(['sand']);
      await journal.record(
        event('spice', shownAt.add(const Duration(minutes: 1))),
      );
      await open(tester);
      final engine = engines.single;
      expect(words(engine, HighlightKind.lookedUp), {'spice'});

      await saveSheet(['water'], when: shownAt.add(const Duration(minutes: 5)));
      await settle(tester);
      expect(words(engine, HighlightKind.cheatSheet), {'water'});
      expect(words(engine, HighlightKind.lookedUp), isEmpty);
      await close(tester);
    });

    macTest('known words are not marked', (tester) async {
      await saveSheet(['sand', 'dune']);
      await journal.record(
        event('spice', shownAt.add(const Duration(minutes: 1))),
      );
      for (final lemma in ['sand', 'spice']) {
        await terms.save(
          Term(
            id: TermId('t-$lemma'),
            normalized: lemma,
            language: 'en',
            lookupCount: 1,
            eventIds: const [],
            status: TermStatus.known,
          ),
        );
      }
      await open(tester);
      final engine = engines.single;
      expect(words(engine, HighlightKind.cheatSheet), {'dune'});
      expect(words(engine, HighlightKind.lookedUp), isEmpty);
      await close(tester);
    });

    macTest('the switches turn their own kinds off', (tester) async {
      await profiles.save(
        const UserProfile(highlights: HighlightPrefs(cheatSheet: false)),
      );
      await saveSheet(['sand']);
      await journal.record(
        event('spice', shownAt.add(const Duration(minutes: 1))),
      );
      await open(tester);
      final engine = engines.single;
      expect(words(engine, HighlightKind.cheatSheet), isEmpty);
      expect(words(engine, HighlightKind.lookedUp), {'spice'});

      await profiles.save(
        const UserProfile(highlights: HighlightPrefs(lookedUp: false)),
      );
      await settle(tester);
      expect(words(engine, HighlightKind.cheatSheet), {'sand'});
      expect(words(engine, HighlightKind.lookedUp), isEmpty);

      await profiles.save(
        const UserProfile(highlights: HighlightPrefs(enabled: false)),
      );
      await settle(tester);
      expect(engine.allHighlights.last.isEmpty, isTrue);

      await profiles.save(const UserProfile());
      await settle(tester);
      expect(words(engine, HighlightKind.cheatSheet), {'sand'});
      expect(words(engine, HighlightKind.lookedUp), {'spice'});
      await close(tester);
    });

    macTest('the open lookup keeps its focus mark beside the words', (
      tester,
    ) async {
      await saveSheet(['sand']);
      await open(tester);
      final engine = engines.single;
      lookupOpen = Completer<void>();
      engine.emit(
        TextSelected(text: 'sand', at: at(1, 0.25), sentence: 'A sand.'),
      );
      await tester.pump();
      final open_ = engine.allHighlights.last;
      expect(open_.ranges[HighlightKind.focus], [at(1, 0.25)]);
      expect(open_.words[HighlightKind.cheatSheet], {'sand'});
      lookupOpen!.complete();
      await tester.pump();
      expect(engine.allHighlights.last.ranges[HighlightKind.focus], isNull);
      expect(engine.allHighlights.last.words[HighlightKind.cheatSheet], {
        'sand',
      });
      await close(tester);
    });
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

  group('the just translated word (T-114)', () {
    List<Locator> recent(_FakeEngine e) =>
        e.allHighlights.last.ranges[HighlightKind.recent] ?? const [];

    Future<void> select(
      WidgetTester tester,
      _FakeEngine e,
      Locator place,
    ) async {
      lookupOpen = Completer<void>();
      e.emit(TextSelected(text: 'sand', at: place, sentence: 'The sand.'));
      await tester.pump();
    }

    Future<void> closeLookup(WidgetTester tester) async {
      lookupOpen!.complete();
      await tester.pump();
      await tester.pump();
    }

    macTest('is marked after the lookup closes and for 10 seconds only', (
      tester,
    ) async {
      await open(tester);
      final engine = engines.single;
      await select(tester, engine, at(1, 0.25));
      expect(recent(engine), isEmpty);
      await closeLookup(tester);
      expect(recent(engine), [at(1, 0.25)]);
      expect(engine.highlights.last, isEmpty);

      await tester.pump(recentHighlightDuration - const Duration(seconds: 1));
      expect(recent(engine), [at(1, 0.25)]);
      await tester.pump(const Duration(seconds: 1));
      expect(engine.allHighlights.last, ReaderHighlights.none);
      await close(tester);
    });

    macTest('a new lookup takes the previous mark off at once', (tester) async {
      await open(tester);
      final engine = engines.single;
      await select(tester, engine, at(1, 0.25));
      await closeLookup(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(recent(engine), [at(1, 0.25)]);

      await select(tester, engine, at(1, 0.5));
      expect(recent(engine), isEmpty);
      expect(engine.highlights.last, [at(1, 0.5)]);
      await closeLookup(tester);
      expect(recent(engine), [at(1, 0.5)]);

      // The first mark's timer is gone: only 10 s after the second lookup
      // the mark leaves.
      await tester.pump(const Duration(seconds: 8));
      expect(recent(engine), [at(1, 0.5)]);
      await tester.pump(const Duration(seconds: 2));
      expect(engine.allHighlights.last, ReaderHighlights.none);
      await close(tester);
    });

    macTest('stays off when the profile has it off', (tester) async {
      await profiles.save(
        const UserProfile(highlights: HighlightPrefs(recent: false)),
      );
      await open(tester);
      final engine = engines.single;
      await select(tester, engine, at(1, 0.25));
      await closeLookup(tester);
      expect(engine.allHighlights.last, ReaderHighlights.none);
      await close(tester);
    });

    macTest('stays off when all highlights are off', (tester) async {
      await profiles.save(
        const UserProfile(highlights: HighlightPrefs(enabled: false)),
      );
      await open(tester);
      final engine = engines.single;
      await select(tester, engine, at(1, 0.25));
      await closeLookup(tester);
      expect(engine.allHighlights.last, ReaderHighlights.none);
      await close(tester);
    });

    macTest('keeps the place from history while it is marked', (tester) async {
      final target = at(2, 0.5);
      await open(tester, locator: target);
      final engine = engines.single;
      await select(tester, engine, at(2, 0.75));
      await closeLookup(tester);
      expect(engine.allHighlights.last.ranges, {
        HighlightKind.focus: [target],
        HighlightKind.recent: [at(2, 0.75)],
      });
      await close(tester);
    });
  });

  group('difficult words (T-117)', () {
    const on = HighlightPrefs(difficult: true);

    Set<String> difficult(_FakeEngine e) =>
        e.allHighlights.last.words[HighlightKind.difficult] ?? const {};

    macTest('the open chapter gives its words above the level', (tester) async {
      await profiles.save(const UserProfile(highlights: on));
      await open(tester);
      final engine = engines.single;
      expect(difficult(engine), {'cargo', 'dusk'});
      expect(generator.texts, ['One.']);
      await close(tester);
    });

    macTest('a switched off highlight computes nothing', (tester) async {
      await open(tester);
      final engine = engines.single;
      expect(engine.allHighlights, isEmpty);
      expect(generator.texts, isEmpty);

      // The master toggle off with the kind on: still nothing.
      await profiles.save(
        const UserProfile(
          highlights: HighlightPrefs(enabled: false, difficult: true),
        ),
      );
      await tester.pump();
      expect(engine.allHighlights, isEmpty);
      expect(generator.texts, isEmpty);
      await close(tester);
    });

    macTest('switching the toggle on and off', (tester) async {
      await open(tester);
      final engine = engines.single;
      await profiles.save(const UserProfile(highlights: on));
      await tester.pump();
      await tester.pump();
      expect(difficult(engine), {'cargo', 'dusk'});

      await profiles.save(const UserProfile());
      await tester.pump();
      expect(engine.allHighlights.last, ReaderHighlights.none);
      await close(tester);
    });

    macTest('a new level or threshold picks again without a new analysis', (
      tester,
    ) async {
      await profiles.save(const UserProfile(highlights: on));
      await open(tester);
      final engine = engines.single;

      await profiles.save(
        const UserProfile(level: CefrLevel.c1, highlights: on),
      );
      await tester.pump();
      expect(difficult(engine), {'dusk'});

      await profiles.save(
        const UserProfile(
          highlights: HighlightPrefs(difficult: true, minFrequencyBars: 5),
        ),
      );
      await tester.pump();
      expect(difficult(engine), {'cargo'});
      expect(generator.texts, ['One.']);
      await close(tester);
    });

    macTest('a word marked known leaves the set', (tester) async {
      await profiles.save(const UserProfile(highlights: on));
      await open(tester);
      final engine = engines.single;
      expect(difficult(engine), {'cargo', 'dusk'});

      await terms.save(
        const Term(
          id: TermId('t-cargo'),
          normalized: 'cargo',
          language: 'en',
          lookupCount: 1,
          eventIds: [],
          status: TermStatus.known,
        ),
      );
      await tester.pump();
      expect(difficult(engine), {'dusk'});
      expect(generator.texts, ['One.']);
      await close(tester);
    });

    Term seen(String word, {int lookups = 1, String language = 'en'}) => Term(
      id: TermId('t-$language-$word'),
      normalized: word,
      language: language,
      lookupCount: lookups,
      eventIds: const [],
    );

    macTest('a looked-up word joins the set whatever its level or name', (
      tester,
    ) async {
      await profiles.save(const UserProfile(highlights: on));
      await open(tester);
      final engine = engines.single;
      expect(difficult(engine), {'cargo', 'dusk'});

      // Below the level, without a level, a proper name: each comes in as
      // soon as the term is saved, without analysing the chapter again.
      await terms.save(seen('apple'));
      await tester.pump();
      expect(difficult(engine), {'cargo', 'dusk', 'apple'});
      await terms.save(seen('mystery', lookups: 2));
      await terms.save(seen('london'));
      await tester.pump();
      expect(difficult(engine), {
        'cargo',
        'dusk',
        'apple',
        'mystery',
        'london',
      });
      expect(generator.texts, ['One.']);
      await close(tester);
    });

    macTest('a translated word is picked on opening, not only later', (
      tester,
    ) async {
      await terms.save(seen('apple'));
      await terms.save(seen('mystery'));
      await profiles.save(const UserProfile(highlights: on));
      await open(tester);
      expect(difficult(engines.single), {'cargo', 'dusk', 'apple', 'mystery'});
      await close(tester);
    });

    macTest('known wins over a lookup; no lookups and other languages do '
        'not count', (tester) async {
      await profiles.save(const UserProfile(highlights: on));
      await open(tester);
      final engine = engines.single;

      await terms.save(seen('apple', lookups: 0));
      await terms.save(seen('mystery', language: 'ru'));
      await tester.pump();
      expect(difficult(engine), {'cargo', 'dusk'});

      await terms.save(seen('apple'));
      await terms.save(seen('dusk').copyWith(status: TermStatus.known));
      await tester.pump();
      expect(difficult(engine), {'cargo', 'apple'});
      expect(generator.texts, ['One.']);
      await close(tester);
    });

    macTest('a translated word stays while the level and threshold change', (
      tester,
    ) async {
      await terms.save(seen('apple'));
      await profiles.save(const UserProfile(highlights: on));
      await open(tester);
      final engine = engines.single;

      await profiles.save(
        const UserProfile(
          level: CefrLevel.c1,
          highlights: HighlightPrefs(difficult: true, minFrequencyBars: 5),
        ),
      );
      await tester.pump();
      // dusk is above c1 but has 2 bars; apple is translated: no threshold.
      expect(difficult(engine), {'apple'});
      expect(generator.texts, ['One.']);
      await close(tester);
    });

    macTest('another chapter has its own set, the old one is dropped', (
      tester,
    ) async {
      await profiles.save(const UserProfile(highlights: on));
      await open(tester);
      final engine = engines.single;

      engines.single.emit(PositionChanged(at(1, 0.1)));
      await tester.pumpAndSettle();
      expect(engine.allHighlights.reversed.skip(1).first.words, isEmpty);
      expect(difficult(engine), {'cargo', 'dusk', 'ember'});
      expect(generator.texts, ['One.', 'Two.']);

      // The same chapter again: nothing is analysed.
      engine.emit(PositionChanged(at(1, 0.6)));
      await tester.pump();
      expect(generator.texts, ['One.', 'Two.']);
      await close(tester);
    });

    macTest('it is drawn together with the place of a translation', (
      tester,
    ) async {
      await profiles.save(const UserProfile(highlights: on));
      await open(tester);
      final engine = engines.single;
      lookupOpen = Completer<void>();
      engine.emit(
        TextSelected(text: 'sand', at: at(0, 0.25), sentence: 'The sand.'),
      );
      await tester.pump();
      expect(engine.allHighlights.last.ranges, {
        HighlightKind.focus: [at(0, 0.25)],
      });
      expect(difficult(engine), {'cargo', 'dusk'});
      lookupOpen!.complete();
      await tester.pump();
      await tester.pump();
      await close(tester);
    });
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
          cheatSheetLogProvider.overrideWithValue(cheatSheets),
          lookupJournalProvider.overrideWithValue(journal),
          termRepositoryProvider.overrideWithValue(terms),
          textAnalyzerProvider.overrideWithValue(_WordAnalyzer()),
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

    macTest('the translate toggle saves, applies and survives a restart', (
      tester,
    ) async {
      await open(tester);
      expect(engines.single.settingsApplied.last.translateOnSelect, isFalse);
      expect(find.byTooltip('Translate: off'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
      await tester.tap(find.byTooltip('Translate: off'));
      await tester.pump();
      await tester.pump();
      expect((await profiles.get()).display.translateOnSelect, isTrue);
      expect(engines.single.settingsApplied.last.translateOnSelect, isTrue);
      expect(find.byTooltip('Translate: on'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      await close(tester);

      // A new screen reads the stored profile.
      await open(tester);
      expect(engines.last.settingsApplied.last.translateOnSelect, isTrue);
      expect(find.byTooltip('Translate: on'), findsOneWidget);
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
            cheatSheetLogProvider.overrideWithValue(cheatSheets),
            lookupJournalProvider.overrideWithValue(journal),
            termRepositoryProvider.overrideWithValue(terms),
            textAnalyzerProvider.overrideWithValue(_WordAnalyzer()),
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

    macTest('a highlight switch in the panel saves the profile', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byTooltip('Text'));
      await tester.pumpAndSettle();
      expect((await profiles.get()).highlights.difficult, isFalse);
      final difficult = find.byKey(const Key('highlight-difficult'));
      await tester.ensureVisible(difficult);
      await tester.tap(difficult);
      await tester.pumpAndSettle();
      var highlights = (await profiles.get()).highlights;
      expect(highlights.difficult, isTrue);
      // Other fields and the display settings stay as they were.
      expect(highlights.cheatSheet, isTrue);
      await tester.tap(find.byKey(const Key('highlight-recent')));
      await tester.pumpAndSettle();
      highlights = (await profiles.get()).highlights;
      expect(highlights.recent, isFalse);
      expect(highlights.difficult, isTrue);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('highlight-recent')))
            .value,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    macTest('with the master switch off the kind switches are inactive', (
      tester,
    ) async {
      await profiles.save(
        const UserProfile(highlights: HighlightPrefs(enabled: false)),
      );
      await open(tester);
      await tester.tap(find.byTooltip('Text'));
      await tester.pumpAndSettle();
      const kinds = [
        'highlight-difficult',
        'highlight-cheat-sheet',
        'highlight-looked-up',
        'highlight-recent',
      ];
      SwitchListTile tile(String key) =>
          tester.widget<SwitchListTile>(find.byKey(Key(key)));
      for (final key in kinds) {
        expect(tile(key).onChanged, isNull, reason: key);
      }
      final master = find.byKey(const Key('highlights-enabled'));
      await tester.ensureVisible(master);
      await tester.tap(master);
      await tester.pumpAndSettle();
      expect((await profiles.get()).highlights.enabled, isTrue);
      for (final key in kinds) {
        expect(tile(key).onChanged, isNotNull, reason: key);
      }
      // The kinds keep their values while the master switch is off.
      await tester.tap(master);
      await tester.pumpAndSettle();
      final highlights = (await profiles.get()).highlights;
      expect(highlights.enabled, isFalse);
      expect(highlights.cheatSheet, isTrue);
      expect(tile('highlight-cheat-sheet').value, isTrue);
      expect(tile('highlight-cheat-sheet').onChanged, isNull);
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

  @override
  Future<UserProfile> update(UserProfile Function(UserProfile) change) {
    _onSave();
    return _inner.update(change);
  }
}

/// A [FakeBookFormatAdapter] whose books have no table of contents and/or
/// hold back the chapters until [gate] completes.
class _WrappedAdapter extends FakeBookFormatAdapter {
  new({this.noToc = false, this.gate});

  final bool noToc;
  final Future<void>? gate;

  @override
  Future<OpenedBook> open(String path) async =>
      _WrappedBook(await super.open(path), noToc: noToc, gate: gate);
}

class _WrappedBook implements OpenedBook {
  new(this.inner, {required this.noToc, required this.gate});

  final OpenedBook inner;
  final bool noToc;
  final Future<void>? gate;

  @override
  List<TocEntry> get toc => noToc ? const [] : inner.toc;

  @override
  List<ChapterRef> get spine => inner.spine;

  @override
  Future<ContentDocument> chapter(ChapterRef ref) async {
    await gate;
    return await inner.chapter(ref);
  }

  @override
  Future<Uint8List> resource(String href) => inner.resource(href);

  @override
  Future<void> close() => inner.close();
}
