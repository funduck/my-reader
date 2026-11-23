import 'dart:typed_data';

import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_api/reader_api.dart';
import 'package:reader_simple/reader_simple.dart';
import 'package:reader_simple/src/block_view.dart' show PressMarkPainter;
import 'package:reader_simple/src/interactions.dart';

import 'fake_text_analyzer.dart';

const _bookId = BookId('book-1');

class _DocBook implements OpenedBook {
  new(this._doc) : spine = const [ChapterRef(href: 'c0.xhtml', index: 0)];

  final ContentDocument _doc;

  @override
  final List<ChapterRef> spine;

  @override
  List<TocEntry> get toc => const [];

  @override
  Future<ContentDocument> chapter(ChapterRef ref) async => _doc;

  @override
  Future<Uint8List> resource(String href) async => throw ArgumentError(href);

  @override
  Future<void> close() async {}
}

class _Harness {
  new(this.engine, this.analyzer, this.events);

  final SimpleReaderEngine engine;
  final FakeTextAnalyzer analyzer;
  final List<ReaderEvent> events;

  /// The tap and selection events, without position reports.
  List<ReaderEvent> get taps => [
    for (final e in events)
      if (e is WordTapped || e is TextSelected) e,
  ];
}

Future<_Harness> _open(WidgetTester tester, OpenedBook book) async {
  final analyzer = FakeTextAnalyzer();
  final engine = SimpleReaderEngine(analyzer: analyzer);
  addTearDown(engine.dispose);
  final events = <ReaderEvent>[];
  final sub = engine.events.listen(events.add);
  addTearDown(sub.cancel);
  await engine.load(book, bookId: _bookId);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Builder(builder: engine.buildView)),
    ),
  );
  await tester.pump();
  return _Harness(engine, analyzer, events);
}

Future<_Harness> _openText(WidgetTester tester, String chapter) =>
    _open(tester, FakeOpenedBook(chapters: [chapter]));

RenderEditable? _findEditable(RenderObject root) {
  if (root is RenderEditable) return root;
  RenderEditable? found;
  root.visitChildren((child) => found ??= _findEditable(child));
  return found;
}

Finder _paragraph(String contains) => find.byWidgetPredicate(
  (w) =>
      w is SelectableText &&
      (w.textSpan?.toPlainText().contains(contains) ?? false),
);

/// The centre of the first occurrence of [word] in the paragraph that
/// contains [inParagraph], in global coordinates.
Offset _centerOf(WidgetTester tester, String inParagraph, String word) {
  final finder = _paragraph(inParagraph);
  final text = tester.widget<SelectableText>(finder).textSpan!.toPlainText();
  final start = text.indexOf(word);
  expect(start, greaterThanOrEqualTo(0), reason: '"$word" in "$text"');
  final editable = _findEditable(tester.renderObject(finder))!;
  final box = editable
      .getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + word.length),
      )
      .first;
  return editable.localToGlobal(box.toRect().center);
}

/// A touch that rests on [at] long enough to look the word up.
Future<void> _tap(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(at);
  await tester.pump(lookupHoldDuration + const Duration(milliseconds: 10));
  await gesture.up();
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
}

/// A press of the primary mouse button on [at], held for [hold], then
/// released.
Future<void> _mouseHold(WidgetTester tester, Offset at, Duration hold) async {
  final gesture = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
  await tester.pump(hold);
  await gesture.up();
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
}

/// The spans of the paragraph that contains [inParagraph] drawn with a
/// background.
List<TextSpan> _marked(WidgetTester tester, String inParagraph) {
  final span = tester.widget<SelectableText>(_paragraph(inParagraph)).textSpan!;
  final result = <TextSpan>[];
  span.visitChildren((s) {
    if (s is TextSpan && s.style?.backgroundColor != null) result.add(s);
    return true;
  });
  return result;
}

/// The words under the press mark of the paragraph that contains
/// [inParagraph].
List<String> _pressedWords(WidgetTester tester, String inParagraph) {
  final marks = find.descendant(
    of: find.ancestor(
      of: _paragraph(inParagraph),
      matching: find.byType(Stack),
    ),
    matching: find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PressMarkPainter,
    ),
  );
  final painter =
      tester.widget<CustomPaint>(marks.first).painter! as PressMarkPainter;
  final box = tester.renderObject<RenderBox>(marks.first);
  final editable = _findEditable(tester.renderObject(_paragraph(inParagraph)))!;
  final text = tester
      .widget<SelectableText>(_paragraph(inParagraph))
      .textSpan!
      .toPlainText();
  return [
    for (final r in painter.boxes)
      () {
        final at = editable
            .getPositionForPoint(box.localToGlobal(r.center))
            .offset;
        final word = wordRangeAt(text, at)!;
        return text.substring(word.$1, word.$2);
      }(),
  ];
}

/// A click of the primary mouse button; a mouse has no selection handles that
/// could catch a second click.
Future<void> _click(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
  await gesture.up();
}

/// Selects `[start, end)` of the paragraph and opens the selection menu.
Future<void> _select(
  WidgetTester tester,
  String inParagraph,
  int start,
  int end,
) async {
  final editable = tester.state<EditableTextState>(
    find.descendant(
      of: _paragraph(inParagraph),
      matching: find.byType(EditableText),
    ),
  );
  editable.userUpdateTextEditingValue(
    editable.textEditingValue.copyWith(
      selection: TextSelection(baseOffset: start, extentOffset: end),
    ),
    SelectionChangedCause.toolbar,
  );
  editable.showToolbar();
  await tester.pump();
}

final _macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

const _fox = 'The quick brown fox jumps. It was over the lazy dog.';

void main() {
  group('tap on a word', () {
    testWidgets('still emits WordTapped through the dim layer', (tester) async {
      final h = await _openText(tester, _fox);
      h.engine.applySettings(const ReaderSettings(dim: 0.5));
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is ColoredBox && w.color == Colors.black.withValues(alpha: 0.5),
        ),
        findsOneWidget,
      );

      await _tap(tester, _centerOf(tester, 'quick', 'brown'));

      expect((h.taps.single as WordTapped).word, 'brown');
    });

    testWidgets('emits WordTapped with word, Locator and sentence', (
      tester,
    ) async {
      final h = await _openText(tester, _fox);
      await _tap(tester, _centerOf(tester, 'quick', 'brown'));

      expect(h.taps, hasLength(1));
      final event = h.taps.single as WordTapped;
      expect(event.word, 'brown');
      expect(event.sentence, 'The quick brown fox jumps.');
      expect(event.at.book, _bookId);
      expect(
        event.at.chapter,
        const ChapterRef(href: 'chapter1.xhtml', index: 0),
      );
      expect(event.at.engineHint, 'simple:1:0:0:10');
      expect(event.at.quote!.exact, 'brown');
      expect(event.at.quote!.prefix, 'The quick ');
      expect(event.at.quote!.suffix, ' fox jumps. It was over the la');
      expect(event.at.progression, closeTo(10 / _fox.length, 1e-9));
    });

    testWidgets('a word in the second sentence gets that sentence', (
      tester,
    ) async {
      final h = await _openText(tester, _fox);
      await _tap(tester, _centerOf(tester, 'quick', 'lazy'));

      final event = h.taps.single as WordTapped;
      expect(event.word, 'lazy');
      expect(event.sentence, 'It was over the lazy dog.');
    });

    testWidgets('punctuation is not part of the word', (tester) async {
      final h = await _openText(tester, 'Well, "stop" now (please)!');
      await _tap(tester, _centerOf(tester, 'Well', 'stop'));
      await _tap(tester, _centerOf(tester, 'Well', 'please'));

      expect(
        [for (final e in h.taps) (e as WordTapped).word],
        ['stop', 'please'],
      );
    });

    testWidgets('an apostrophe and a hyphen inside a word stay', (
      tester,
    ) async {
      final h = await _openText(tester, "She didn't like a well-known 'fox'.");
      await _tap(tester, _centerOf(tester, 'didn', "didn't"));
      await _tap(tester, _centerOf(tester, 'didn', 'well-known'));
      await _tap(tester, _centerOf(tester, 'didn', 'fox'));

      expect(
        [for (final e in h.taps) (e as WordTapped).word],
        ["didn't", 'well-known', 'fox'],
      );
    });

    testWidgets('a tap on blank space between words emits nothing', (
      tester,
    ) async {
      final h = await _openText(tester, 'one   two');
      // The middle of the three spaces.
      await _tap(tester, _centerOf(tester, 'one', '  '));
      expect(h.taps, isEmpty);
    });

    testWidgets('a double click selects the word and is not a tap', (
      tester,
    ) async {
      final h = await _openText(tester, _fox);
      final at = _centerOf(tester, 'quick', 'brown');
      await _click(tester, at);
      await tester.pump(kDoubleTapMinTime);
      await _click(tester, at);
      await tester.pump(kDoubleTapTimeout * 2);

      expect(h.taps, isEmpty);
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText).first,
      );
      final selection = editable.textEditingValue.selection;
      expect(selection.textInside(editable.textEditingValue.text), 'brown');
    }, variant: _macOS);

    testWidgets('a hold that only clears a selection emits nothing', (
      tester,
    ) async {
      final h = await _openText(tester, _fox);
      final quick = _centerOf(tester, 'quick', 'quick');
      await _click(tester, quick);
      await tester.pump(kDoubleTapMinTime);
      await _click(tester, quick);
      await tester.pump(kDoubleTapTimeout * 2);
      expect(h.taps, isEmpty);
      final hold = lookupHoldDuration + const Duration(milliseconds: 10);
      await _mouseHold(tester, _centerOf(tester, 'quick', 'fox'), hold);
      expect(h.taps, isEmpty);

      // The selection is gone, the next hold counts.
      await _mouseHold(tester, _centerOf(tester, 'quick', 'fox'), hold);
      expect((h.taps.single as WordTapped).word, 'fox');
    }, variant: _macOS);

    testWidgets('the Locator of a tap in a list item points into the item', (
      tester,
    ) async {
      final h = await _open(
        tester,
        _DocBook(
          const ContentDocument([
            ListBlock(
              ordered: false,
              items: [
                [TextInline('first one')],
                [TextInline('second item here')],
              ],
            ),
          ]),
        ),
      );
      await _tap(tester, _centerOf(tester, 'second', 'item'));

      final event = h.taps.single as WordTapped;
      expect(event.word, 'item');
      expect(event.sentence, 'second item here');
      // "first one" (9) + the newline + "second " (7).
      expect(event.at.engineHint, 'simple:1:0:0:17');
      expect(event.at.quote!.exact, 'item');
    });

    testWidgets('a tap in a quoted paragraph points into the block', (
      tester,
    ) async {
      final h = await _open(
        tester,
        _DocBook(
          const ContentDocument([
            ParagraphBlock([TextInline('Before.')]),
            QuoteBlock([
              ParagraphBlock([TextInline('one')]),
              ParagraphBlock([TextInline('two three')]),
            ]),
          ]),
        ),
      );
      await _tap(tester, _centerOf(tester, 'two', 'three'));

      final event = h.taps.single as WordTapped;
      expect(event.word, 'three');
      // Block 1; "one" (3) + the newline + "two " (4).
      expect(event.at.engineHint, 'simple:1:0:1:8');
    });

    testWidgets('no event after dispose', (tester) async {
      final h = await _openText(tester, _fox);
      await tester.startGesture(
        _centerOf(tester, 'quick', 'brown'),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(lookupHoldDuration ~/ 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(lookupHoldDuration * 2);
      expect(h.taps, isEmpty);
    }, variant: _macOS);
  });

  group('hold to look up', () {
    const early = Duration(milliseconds: 400);
    final full = lookupHoldDuration + const Duration(milliseconds: 10);

    bool menuShown() =>
        find.text('Copy').evaluate().isNotEmpty ||
        find.text('Select all').evaluate().isNotEmpty ||
        find.text('Translate').evaluate().isNotEmpty;

    EditableTextState editableOf(WidgetTester tester) =>
        tester.state<EditableTextState>(find.byType(EditableText).first);

    test('lookupHoldDuration is 500 ms', () {
      expect(lookupHoldDuration, const Duration(milliseconds: 500));
    });

    testWidgets('touch marks the word at once and emits nothing', (
      tester,
    ) async {
      final h = await _openText(tester, _fox);
      final gesture = await tester.startGesture(
        _centerOf(tester, 'quick', 'brown'),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(_pressedWords(tester, 'quick'), ['brown']);
      expect(h.taps, isEmpty);
      await gesture.up();
      await tester.pump(kDoubleTapTimeout * 2);
      expect(h.taps, isEmpty);
    });

    testWidgets('a touch held for 500 ms emits one WordTapped', (tester) async {
      final h = await _openText(tester, _fox);
      final gesture = await tester.startGesture(
        _centerOf(tester, 'quick', 'brown'),
      );
      await tester.pump(full);
      await gesture.up();
      await tester.pump(kDoubleTapTimeout * 2);

      final event = h.taps.single as WordTapped;
      expect(event.word, 'brown');
      expect(event.sentence, 'The quick brown fox jumps.');
      expect(event.at.engineHint, 'simple:1:0:0:10');
      expect(_pressedWords(tester, 'quick'), isEmpty);
    });

    testWidgets('after a touch hold there is no selection and no toolbar', (
      tester,
    ) async {
      await _openText(tester, _fox);
      final gesture = await tester.startGesture(
        _centerOf(tester, 'quick', 'brown'),
      );
      await tester.pump(full);
      await gesture.up();
      await tester.pump(kDoubleTapTimeout * 2);

      expect(editableOf(tester).textEditingValue.selection.isCollapsed, isTrue);
      expect(menuShown(), isFalse);
    });

    testWidgets('a touch released after 400 ms emits nothing', (tester) async {
      final h = await _openText(tester, _fox);
      final gesture = await tester.startGesture(
        _centerOf(tester, 'quick', 'brown'),
      );
      await tester.pump(early);
      await gesture.up();
      await tester.pump(kDoubleTapTimeout * 2);

      expect(h.taps, isEmpty);
      expect(_pressedWords(tester, 'quick'), isEmpty);
      expect(menuShown(), isFalse);
    });

    testWidgets('a touch that moves 20 px at 100 ms emits nothing', (
      tester,
    ) async {
      final h = await _openText(tester, _fox);
      final gesture = await tester.startGesture(
        _centerOf(tester, 'quick', 'brown'),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(full);
      await gesture.up();
      await tester.pump(kDoubleTapTimeout * 2);

      expect(h.taps, isEmpty);
      expect(_pressedWords(tester, 'quick'), isEmpty);
    });

    testWidgets('a hold on blank space marks and emits nothing', (
      tester,
    ) async {
      final h = await _openText(tester, 'one   two');
      final gesture = await tester.startGesture(_centerOf(tester, 'one', '  '));
      await tester.pump(full);
      expect(_pressedWords(tester, 'one'), isEmpty);
      await gesture.up();
      await tester.pump(kDoubleTapTimeout * 2);
      expect(h.taps, isEmpty);
    });

    testWidgets('the press mark does not replace the reader highlight', (
      tester,
    ) async {
      final h = await _openText(tester, _fox);
      await _tap(tester, _centerOf(tester, 'quick', 'brown'));
      final at = (h.taps.single as WordTapped).at;
      h.engine.highlight([at]);
      await tester.pump();

      final gesture = await tester.startGesture(
        _centerOf(tester, 'quick', 'lazy'),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(_pressedWords(tester, 'quick'), ['lazy']);
      expect([for (final s in _marked(tester, 'quick')) s.text], ['brown']);
      await gesture.up();
      await tester.pump(kDoubleTapTimeout * 2);
      expect(_pressedWords(tester, 'quick'), isEmpty);
      expect([for (final s in _marked(tester, 'quick')) s.text], ['brown']);
    });

    testWidgets('a mouse held for 500 ms emits one WordTapped', (tester) async {
      final h = await _openText(tester, _fox);
      final gesture = await tester.startGesture(
        _centerOf(tester, 'quick', 'brown'),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(_pressedWords(tester, 'quick'), ['brown']);
      expect(h.taps, isEmpty);
      await tester.pump(full);
      expect((h.taps.single as WordTapped).word, 'brown');
      await gesture.up();
      await tester.pump(kDoubleTapTimeout * 2);
      expect(h.taps, hasLength(1));
      expect(_pressedWords(tester, 'quick'), isEmpty);
    }, variant: _macOS);

    testWidgets('a mouse released after 400 ms emits nothing', (tester) async {
      final h = await _openText(tester, _fox);
      await _mouseHold(tester, _centerOf(tester, 'quick', 'brown'), early);
      await tester.pump(full);
      expect(h.taps, isEmpty);
      expect(_pressedWords(tester, 'quick'), isEmpty);
    }, variant: _macOS);

    testWidgets('a mouse drag selects and emits no lookup', (tester) async {
      final h = await _openText(tester, _fox);
      final gesture = await tester.startGesture(
        _centerOf(tester, 'quick', 'quick'),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(_centerOf(tester, 'quick', 'fox'));
      await tester.pump(full);
      await gesture.up();
      await tester.pump(kDoubleTapTimeout * 2);

      expect(h.taps, isEmpty);
      expect(_pressedWords(tester, 'quick'), isEmpty);
      expect(
        editableOf(tester).textEditingValue.selection.isCollapsed,
        isFalse,
      );
    }, variant: _macOS);
  });

  group('sentence at a paragraph boundary', () {
    // The first paragraph does not end with a sentence mark; the second
    // continues the thought. A splitter run over both would glue them.
    const first = 'The old man walked slowly down the road';
    const second = 'and then he stopped. A dog barked.';

    testWidgets('the end of a paragraph is not joined with the next one', (
      tester,
    ) async {
      final h = await _openText(tester, '$first\n\n$second');
      await _tap(tester, _centerOf(tester, 'old man', 'road'));

      final event = h.taps.single as WordTapped;
      expect(event.word, 'road');
      expect(event.sentence, first);
      expect(event.sentence, isNot(contains('and then')));
      expect(h.analyzer.sentenceCalls, [first]);
    });

    testWidgets('the start of a paragraph is not joined with the previous', (
      tester,
    ) async {
      final h = await _openText(tester, '$first\n\n$second');
      await _tap(tester, _centerOf(tester, 'and then', 'and'));

      final event = h.taps.single as WordTapped;
      expect(event.word, 'and');
      expect(event.sentence, 'and then he stopped.');
      expect(h.analyzer.sentenceCalls, [second]);
    });
  });

  group('selection', () {
    testWidgets('the Translate button emits TextSelected', (tester) async {
      final h = await _openText(tester, _fox);
      await _select(tester, 'quick', 4, 15);

      expect(find.text('Translate'), findsOneWidget);
      await tester.tap(find.text('Translate'));
      await tester.pump();

      expect(h.taps, hasLength(1));
      final event = h.taps.single as TextSelected;
      expect(event.text, 'quick brown');
      expect(event.sentence, 'The quick brown fox jumps.');
      expect(event.at.engineHint, 'simple:1:0:0:4');
      expect(event.at.quote!.exact, 'quick brown');
      expect(event.at.chapter.index, 0);
      expect(find.text('Translate'), findsNothing);
    });

    testWidgets('a selection over two sentences gives both', (tester) async {
      final h = await _openText(tester, _fox);
      await _select(tester, 'quick', 16, 29);
      await tester.tap(find.text('Translate'));
      await tester.pump();

      final event = h.taps.single as TextSelected;
      expect(event.text, 'fox jumps. It');
      expect(event.sentence, _fox);
    });

    testWidgets('spaces around the selection are cut off', (tester) async {
      final h = await _openText(tester, _fox);
      await _select(tester, 'quick', 3, 16);
      await tester.tap(find.text('Translate'));
      await tester.pump();

      final event = h.taps.single as TextSelected;
      expect(event.text, 'quick brown');
      expect(event.at.engineHint, 'simple:1:0:0:4');
    });

    testWidgets('there is no Translate button without a selection', (
      tester,
    ) async {
      await _openText(tester, _fox);
      await tester.tap(_paragraph('quick'), buttons: kSecondaryButton);
      await tester.pump();
      expect(find.text('Translate'), findsNothing);
    });
  });

  group('highlight', () {
    testWidgets('a Locator from an event is drawn with a background', (
      tester,
    ) async {
      final h = await _openText(tester, _fox);
      await _tap(tester, _centerOf(tester, 'quick', 'brown'));
      final at = (h.taps.single as WordTapped).at;

      h.engine.highlight([at]);
      await tester.pump();

      expect([for (final s in _marked(tester, 'quick')) s.text], ['brown']);
      expect(
        tester
            .widget<SelectableText>(_paragraph('quick'))
            .textSpan!
            .toPlainText(),
        _fox,
      );
    });

    testWidgets('a phrase over inline styles and a new call replaces', (
      tester,
    ) async {
      final h = await _open(
        tester,
        _DocBook(
          const ContentDocument([
            ParagraphBlock([
              TextInline('plain '),
              BoldInline([TextInline('heavy words')]),
              TextInline(' after'),
            ]),
          ]),
        ),
      );
      const text = 'plain heavy words after';
      Locator at(String exact, int offset) => Locator(
        book: _bookId,
        chapter: h.engine.chapter.value!.ref!,
        progression: 0,
        quote: TextQuote.fromText(text, offset, offset + exact.length),
        engineHint: 'simple:1:0:0:$offset',
      );

      h.engine.highlight([at('in heavy wor', 3)]);
      await tester.pump();
      expect(
        [for (final s in _marked(tester, 'plain')) s.text],
        ['in ', 'heavy wor'],
      );

      h.engine.highlight([at('words after', 12)]);
      await tester.pump();
      expect(
        [for (final s in _marked(tester, 'plain')) s.text],
        ['words', ' after'],
      );

      h.engine.highlight(const []);
      await tester.pump();
      expect(_marked(tester, 'plain'), isEmpty);
    });

    testWidgets('a Locator of another chapter or a lost quote is skipped', (
      tester,
    ) async {
      final h = await _openText(tester, _fox);
      final chapter = h.engine.chapter.value!.ref!;
      h.engine.highlight([
        const Locator(
          book: _bookId,
          chapter: ChapterRef(href: 'other.xhtml', index: 4),
          progression: 0,
          quote: TextQuote(exact: 'quick'),
        ),
        Locator(
          book: _bookId,
          chapter: chapter,
          progression: 0.5,
          quote: const TextQuote(exact: 'missing'),
        ),
        Locator(book: _bookId, chapter: chapter, progression: 0.5),
      ]);
      await tester.pump();
      expect(_marked(tester, 'quick'), isEmpty);
    });
  });

  group('word and sentence helpers', () {
    test('wordRangeAt takes the word before the caret at its end', () {
      expect(wordRangeAt('ab cd', 0), (0, 2));
      expect(wordRangeAt('ab cd', 2), (0, 2));
      expect(wordRangeAt('ab cd', 3), (3, 5));
      expect(wordRangeAt('ab cd', 5), (3, 5));
      expect(wordRangeAt('ab  cd', 3), isNull);
      expect(wordRangeAt('', 0), isNull);
    });

    test('wordRangeAt knows letters and digits of any alphabet', () {
      expect(wordRangeAt('Привет, мир', 8), (8, 11));
      expect(wordRangeAt('in 1984, then', 4), (3, 7));
    });

    test('sentenceAround falls back to the whole text', () {
      final analyzer = _NoSentences();
      expect(sentenceAround(analyzer, ' some text ', 1, 5), 'some text');
    });
  });
}

class _NoSentences implements TextAnalyzer {
  @override
  List<SentenceSpan> sentences(String text) => const [];

  @override
  List<TextToken> tokens(String text) => const [];

  @override
  String lemma(String word) => word;
}
