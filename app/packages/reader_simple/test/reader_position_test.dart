import 'dart:typed_data';

import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_api/reader_api.dart';
import 'package:reader_simple/reader_simple.dart';
import 'package:reader_simple/src/position.dart';
import 'package:reader_simple/src/simple_reader_engine.dart'
    show positionInterval;

const _bookId = BookId('book-1');

/// Long paragraphs, several lines each, with a unique word every few
/// characters: `p<paragraph>-w<word>`.
ContentDocument _chapterDoc(int chapter, {int paragraphs = 30}) =>
    ContentDocument([
      for (var p = 0; p < paragraphs; p++)
        ParagraphBlock([
          TextInline(
            [for (var w = 0; w < 120; w++) 'c$chapter-p$p-w$w'].join(' '),
          ),
        ]),
    ]);

class _Book implements OpenedBook {
  new(this._docs)
    : spine = [
        for (var i = 0; i < _docs.length; i++)
          ChapterRef(href: 'c$i.xhtml', index: i),
      ];

  final List<ContentDocument> _docs;

  @override
  final List<ChapterRef> spine;

  @override
  List<TocEntry> get toc => const [];

  @override
  Future<ContentDocument> chapter(ChapterRef ref) async => _docs[ref.index];

  @override
  Future<Uint8List> resource(String href) async => throw ArgumentError(href);

  @override
  Future<void> close() async {}
}

_Book _book() => _Book([_chapterDoc(0), _chapterDoc(1)]);

Widget _app(SimpleReaderEngine engine) => MaterialApp(
  home: Scaffold(body: Builder(builder: engine.buildView)),
);

class _Opened {
  new(this.engine, this.events);

  final SimpleReaderEngine engine;

  /// Every [PositionChanged] locator, in order.
  final List<Locator> events;
}

Future<_Opened> _open(
  WidgetTester tester, {
  Locator? at,
  OpenedBook? book,
}) async {
  final engine = SimpleReaderEngine();
  final events = <Locator>[];
  final sub = engine.events.listen((e) {
    if (e is PositionChanged) events.add(e.locator);
  });
  addTearDown(() async {
    await sub.cancel();
    await engine.dispose();
  });
  await engine.load(book ?? _book(), bookId: _bookId, at: at);
  await tester.pumpWidget(_app(engine));
  await tester.pump();
  // Let the throttle's cooldown run out.
  await tester.pump(positionInterval);
  return _Opened(engine, events);
}

/// Drags the list up by [dy] and lets it settle and the throttle expire.
Future<void> _scrollBy(WidgetTester tester, double dy) async {
  await tester.drag(find.byType(Scrollable).first, Offset(0, -dy));
  await tester.pumpAndSettle();
  await tester.pump(positionInterval);
}

BlockPosition _hint(Locator l) {
  final parts = l.engineHint!.split(':');
  return BlockPosition(int.parse(parts[3]), int.parse(parts[4]));
}

void main() {
  group('PositionChanged', () {
    testWidgets('is emitted at the start with a full Locator', (tester) async {
      final opened = await _open(tester);
      expect(opened.events, hasLength(1));
      final locator = opened.events.single;
      expect(locator.book, _bookId);
      expect(locator.chapter, const ChapterRef(href: 'c0.xhtml', index: 0));
      expect(locator.progression, 0);
      expect(locator.engineHint, 'simple:1:0:0:0');
      expect(locator.quote?.exact, startsWith('c0-p0-w0 c0-p0-w1'));
      expect(opened.engine.currentLocator(), locator);
    });

    testWidgets('a scroll gives a later position in the same chapter', (
      tester,
    ) async {
      final opened = await _open(tester);
      await _scrollBy(tester, 3000);
      final last = opened.events.last;
      expect(opened.events.length, greaterThan(1));
      expect(last.chapter.index, 0);
      expect(last.progression, greaterThan(0));
      expect(_hint(last).block, greaterThan(0));
      // The quote is the text of the first visible line of that block.
      expect(last.quote!.exact, contains('c0-p${_hint(last).block}-w'));
      expect(opened.engine.currentLocator(), last);
    });

    testWidgets('exactly once per 500 ms while scrolling', (tester) async {
      final opened = await _open(tester);
      final start = tester.binding.clock.now();
      final times = <int>[];
      final sub = opened.engine.events.listen((e) {
        if (e is PositionChanged) {
          times.add(
            tester.binding.clock.now().difference(start).inMilliseconds,
          );
        }
      });
      addTearDown(sub.cancel);
      // A steady drag: every 100 ms of fake time the list moves.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Scrollable).first),
      );
      for (var i = 0; i < 40; i++) {
        await gesture.moveBy(const Offset(0, -40));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      // The drag lasted 4 s. The first event comes when the list starts to
      // move (after the touch slop), then one every 500 ms, not more often.
      expect(times.length, greaterThanOrEqualTo(8));
      expect(times.first, lessThanOrEqualTo(300));
      expect([
        for (var i = 1; i < 8; i++) times[i] - times[i - 1],
      ], everyElement(500));
    });

    testWidgets('the same position is not reported twice', (tester) async {
      final opened = await _open(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      expect(opened.events, hasLength(1));
    });
  });

  group('position -> Locator -> goTo', () {
    testWidgets('a new engine opens at the same block and line', (
      tester,
    ) async {
      final first = await _open(tester);
      await _scrollBy(tester, 2300);
      final saved = first.engine.currentLocator()!;
      final at = _hint(saved);
      expect(at.block, greaterThan(0));
      expect(at.offset, greaterThan(0), reason: 'must land inside a block');

      await tester.pumpWidget(const SizedBox());
      final second = await _open(tester, at: saved);
      expect(second.engine.currentLocator(), saved);
      expect(second.events.last, saved);
    });

    testWidgets('goTo on the same engine returns to the same place', (
      tester,
    ) async {
      final opened = await _open(tester);
      await _scrollBy(tester, 2300);
      final saved = opened.engine.currentLocator()!;
      await _scrollBy(tester, 4000);
      expect(opened.engine.currentLocator(), isNot(saved));

      await opened.engine.goTo(saved);
      await tester.pumpAndSettle();
      expect(opened.engine.currentLocator(), saved);
    });

    testWidgets('survives a JSON round trip of the Locator', (tester) async {
      final first = await _open(tester);
      await _scrollBy(tester, 1700);
      final saved = first.engine.currentLocator()!;
      final restored = Locator.fromJson(saved.toJson());

      await first.engine.goTo(
        const Locator(
          book: _bookId,
          chapter: ChapterRef(href: 'c0.xhtml', index: 0),
          progression: 0,
        ),
      );
      await tester.pumpAndSettle();
      await first.engine.goTo(restored);
      await tester.pumpAndSettle();
      expect(first.engine.currentLocator(), saved);
    });

    testWidgets('works in another chapter', (tester) async {
      final first = await _open(tester);
      await first.engine.goTo(
        const Locator(
          book: _bookId,
          chapter: ChapterRef(href: 'c1.xhtml', index: 1),
          progression: 0,
        ),
      );
      await tester.pumpAndSettle();
      await _scrollBy(tester, 1900);
      final saved = first.engine.currentLocator()!;
      expect(saved.chapter.index, 1);

      await tester.pumpWidget(const SizedBox());
      final second = await _open(tester, at: saved);
      expect(second.engine.currentLocator(), saved);
    });

    testWidgets('a broken engineHint: the TextQuote finds the place', (
      tester,
    ) async {
      final first = await _open(tester);
      await _scrollBy(tester, 2300);
      final saved = first.engine.currentLocator()!;

      // The hint is garbage, out of range, for another chapter, and for
      // another place. The progression is wrong too: only the quote is right.
      for (final hint in [
        'garbage',
        '',
        'simple:1:0:99999:0',
        'simple:1:1:${_hint(saved).block}:${_hint(saved).offset}',
        'simple:1:0:${_hint(saved).block + 3}:0',
      ]) {
        await first.engine.goTo(
          Locator(
            book: _bookId,
            chapter: saved.chapter,
            progression: 0,
            quote: saved.quote,
            engineHint: hint,
          ),
        );
        await tester.pumpAndSettle();
        expect(first.engine.currentLocator(), saved, reason: 'hint "$hint"');
      }
    });

    testWidgets('a hint of another place is caught by the quote', (
      tester,
    ) async {
      final first = await _open(tester);
      await _scrollBy(tester, 2300);
      final saved = first.engine.currentLocator()!;
      // In range, well formed, but where the quote is not.
      await first.engine.goTo(
        Locator(
          book: _bookId,
          chapter: saved.chapter,
          progression: 0.9,
          quote: saved.quote,
          engineHint: 'simple:1:0:2:10',
        ),
      );
      await tester.pumpAndSettle();
      expect(first.engine.currentLocator(), saved);
    });

    testWidgets('without hint and quote: the progression decides', (
      tester,
    ) async {
      final opened = await _open(tester);
      final expected = ChapterText.of(_chapterDoc(0)).fromProgression(0.5);
      await opened.engine.goTo(
        const Locator(
          book: _bookId,
          chapter: ChapterRef(href: 'c0.xhtml', index: 0),
          progression: 0.5,
        ),
      );
      await tester.pumpAndSettle();
      final now = opened.engine.currentLocator()!;
      expect(_hint(now).block, expected.block);
      expect(now.progression, closeTo(0.5, 0.01));
    });

    testWidgets('a quote that is not in the text falls back to progression', (
      tester,
    ) async {
      final opened = await _open(tester);
      final expected = ChapterText.of(_chapterDoc(0)).fromProgression(0.25);
      await opened.engine.goTo(
        const Locator(
          book: _bookId,
          chapter: ChapterRef(href: 'c0.xhtml', index: 0),
          progression: 0.25,
          quote: TextQuote(exact: 'text from another edition'),
          engineHint: 'garbage',
        ),
      );
      await tester.pumpAndSettle();
      expect(_hint(opened.engine.currentLocator()!).block, expected.block);
    });

    testWidgets('goTo emits the new position', (tester) async {
      final opened = await _open(tester);
      await _scrollBy(tester, 2300);
      final saved = opened.engine.currentLocator()!;
      await _scrollBy(tester, 4000);
      opened.events.clear();
      await opened.engine.goTo(saved);
      await tester.pumpAndSettle();
      await tester.pump(positionInterval);
      expect(opened.events.last, saved);
    });
  });
}
