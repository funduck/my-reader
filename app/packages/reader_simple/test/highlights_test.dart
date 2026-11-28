import 'dart:math' as math;

import 'package:core/domain_books.dart';
import 'package:core_testing/core_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_api/reader_api.dart';
import 'package:reader_simple/reader_simple.dart';
import 'package:reader_simple/src/block_view.dart';
import 'package:reader_simple/src/highlight_plates.dart';
import 'package:reader_simple/src/reader_style.dart';

import 'fake_text_analyzer.dart';
import 'plate_marks.dart';

const _bookId = BookId('book-1');

/// An analyzer that knows a few word forms and counts its `lemma` calls.
class _Analyzer extends FakeTextAnalyzer {
  new();

  static const Map<String, String> _forms = {
    'running': 'run',
    'runs': 'run',
    'ran': 'run',
  };

  int lemmaCalls = 0;

  @override
  String lemma(String word) {
    lemmaCalls++;
    final lower = word.toLowerCase();
    return _forms[lower] ?? lower;
  }
}

class _Harness {
  new(this.engine, this.analyzer);

  final SimpleReaderEngine engine;
  final _Analyzer analyzer;

  Color? color(HighlightKind kind) =>
      engine.style.value.highlightOf(kind).background;
}

Future<_Harness> _open(WidgetTester tester, List<String> paragraphs) async {
  final analyzer = _Analyzer();
  final engine = SimpleReaderEngine(analyzer: analyzer);
  addTearDown(engine.dispose);
  await engine.load(
    FakeOpenedBook(chapters: [paragraphs.join('\n\n')]),
    bookId: _bookId,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Builder(builder: engine.buildView)),
    ),
  );
  await tester.pump();
  return _Harness(engine, analyzer);
}

Locator _at(
  _Harness h,
  String chapterText,
  String exact, {
  int occurrence = 0,
}) {
  var start = -1;
  for (var i = 0; i <= occurrence; i++) {
    start = chapterText.indexOf(exact, start + 1);
  }
  return Locator(
    book: _bookId,
    chapter: h.engine.chapter.value!.ref!,
    progression: 0,
    quote: TextQuote.fromText(chapterText, start, start + exact.length),
  );
}

ReaderHighlights _words(Map<HighlightKind, Set<String>> words) =>
    ReaderHighlights(words: words);

void main() {
  const paragraphs = [
    'She runs fast. Then she ran home.',
    'Nothing to see here.',
    'Running is fun, said the dog.',
  ];

  group('words', () {
    testWidgets('a word is marked everywhere, in every form of its lemma', (
      tester,
    ) async {
      final h = await _open(tester, paragraphs);
      h.engine.highlight(
        _words({
          HighlightKind.lookedUp: {'run'},
        }),
      );
      await tester.pump();

      final blue = h.color(HighlightKind.lookedUp)!;
      expect(allMarks(tester), [
        ('runs', blue),
        ('ran', blue),
        ('Running', blue),
      ]);
    });

    testWidgets('each kind is drawn in its own style', (tester) async {
      final h = await _open(tester, paragraphs);
      h.engine.highlight(
        _words({
          HighlightKind.recent: {'dog'},
          HighlightKind.difficult: {'fast', 'fun'},
        }),
      );
      await tester.pump();

      final recent = h.color(HighlightKind.recent)!;
      final difficult = h.color(HighlightKind.difficult)!;
      expect(recent, isNot(difficult));
      expect(allMarks(tester), [
        ('fast', difficult),
        ('fun', difficult),
        ('dog', recent),
      ]);
    });

    testWidgets('a word that is not in a set is not marked', (tester) async {
      final h = await _open(tester, paragraphs);
      h.engine.highlight(
        _words({
          HighlightKind.lookedUp: {'runn', 'ru', 'to'},
        }),
      );
      await tester.pump();
      expect(allMarks(tester).map((m) => m.$1), ['to']);
    });

    testWidgets('on a word of two kinds the earlier kind is drawn', (
      tester,
    ) async {
      final h = await _open(tester, paragraphs);
      h.engine.highlight(
        _words({
          HighlightKind.difficult: {'run', 'fast'},
          HighlightKind.cheatSheet: {'run'},
          HighlightKind.lookedUp: {'fast'},
        }),
      );
      await tester.pump();

      expect(allMarks(tester), [
        ('runs', h.color(HighlightKind.cheatSheet)),
        ('fast', h.color(HighlightKind.lookedUp)),
        ('ran', h.color(HighlightKind.cheatSheet)),
        ('Running', h.color(HighlightKind.cheatSheet)),
      ]);
    });

    testWidgets('a place beats a word of a later kind and not of an earlier', (
      tester,
    ) async {
      final h = await _open(tester, paragraphs);
      final text = paragraphs.join('\n\n');
      h.engine.highlight(
        ReaderHighlights(
          ranges: {
            HighlightKind.focus: [_at(h, text, 'runs fast')],
            HighlightKind.difficult: [_at(h, text, 'ran home')],
          },
          words: const {
            HighlightKind.difficult: {'run', 'fast'},
            HighlightKind.recent: {'home'},
          },
        ),
      );
      await tester.pump();

      expect(allMarks(tester), [
        ('runs fast', h.color(HighlightKind.focus)),
        ('ran ', h.color(HighlightKind.difficult)),
        ('home', h.color(HighlightKind.recent)),
        ('Running', h.color(HighlightKind.difficult)),
      ]);
    });

    testWidgets('words and the text stay the same under the marks', (
      tester,
    ) async {
      final h = await _open(tester, paragraphs);
      h.engine.highlight(
        _words({
          HighlightKind.recent: {'run'},
        }),
      );
      await tester.pump();
      expect([
        for (final w in tester.widgetList<SelectableText>(
          find.byType(SelectableText),
        ))
          w.textSpan!.toPlainText(),
      ], paragraphs);
    });
  });

  group('ranges', () {
    testWidgets('a place is drawn in the style of its kind', (tester) async {
      final h = await _open(tester, paragraphs);
      final text = paragraphs.join('\n\n');
      h.engine.highlight(
        ReaderHighlights(
          ranges: {
            HighlightKind.recent: [_at(h, text, 'Nothing')],
            HighlightKind.focus: [_at(h, text, 'dog')],
          },
        ),
      );
      await tester.pump();

      expect(allMarks(tester), [
        ('Nothing', h.color(HighlightKind.recent)),
        ('dog', h.color(HighlightKind.focus)),
      ]);
    });

    testWidgets('the focus style is the former single highlight', (
      tester,
    ) async {
      final h = await _open(tester, paragraphs);
      expect(h.color(HighlightKind.focus), const Color(0x80FFEB3B));
    });

    testWidgets('empty highlights clear every kind', (tester) async {
      final h = await _open(tester, paragraphs);
      final text = paragraphs.join('\n\n');
      h.engine.highlight(
        ReaderHighlights(
          ranges: {
            HighlightKind.focus: [_at(h, text, 'dog')],
          },
          words: const {
            HighlightKind.difficult: {'run'},
          },
        ),
      );
      await tester.pump();
      expect(allMarks(tester), isNotEmpty);

      h.engine.highlight(ReaderHighlights.none);
      await tester.pump();
      expect(allMarks(tester), isEmpty);
    });

    testWidgets('an underline style draws a line and keeps the text', (
      tester,
    ) async {
      const style = HighlightStyle(underline: Color(0xFFFF0000));
      expect(style.textStyle.decoration, TextDecoration.underline);
      expect(style.textStyle.decorationColor, const Color(0xFFFF0000));
      expect(style.textStyle.backgroundColor, isNull);
      expect(const HighlightStyle().textStyle.decoration, isNull);
    });
  });

  group('plates', () {
    const radius = Radius.circular(HighlightPlateShape.radius);

    // The box of the text [start, end) of the one paragraph on screen, as the
    // paragraph lays it out, in the coordinates of the plates, one per line.
    List<Rect> boxes(WidgetTester tester, int start, int end) {
      final editable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final plates = tester.renderObject<RenderHighlightPlates>(
        find.byType(HighlightPlates),
      );
      final toPlates = editable.getTransformTo(plates);
      return [
        for (final box in editable.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        ))
          MatrixUtils.transformRect(toPlates, box.toRect()),
      ];
    }

    // The plate of a line box: as wide as the box plus the padding, as tall
    // as the font (the test font: ascent 0.75 em, descent 0.25 em) and centred
    // halfway between the baseline and the top of the capitals. The bottom
    // of the box is the bottom of the line; the Material theme shares the
    // extra line height evenly above and below the font. Defaults: font
    // size 18, line height 1.5.
    Rect widened(Rect box, {double fontSize = 18, double lineHeight = 1.5}) {
      final baseline =
          box.bottom - (fontSize * lineHeight - fontSize) / 2 - fontSize * 0.25;
      final centre = baseline - fontSize * HighlightPlateShape.capHeight / 2;
      final half = math.min(
        fontSize / 2 + HighlightPlateShape.verticalPadding,
        fontSize * lineHeight / 2 - 1,
      );
      return Rect.fromLTRB(
        box.left - HighlightPlateShape.horizontalPadding,
        centre - half,
        box.right + HighlightPlateShape.horizontalPadding,
        centre + half,
      );
    }

    // A view 200 px wide: 168 px of text, nine letters of the test font.
    void narrow(WidgetTester tester) {
      tester.view
        ..physicalSize = const Size(200, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Future<_Harness> openOne(WidgetTester tester, String text) {
      narrow(tester);
      return _open(tester, [text]);
    }

    List<Plate> plates(WidgetTester tester) =>
        platesOf(tester, find.byType(SelectableText));

    testWidgets('the plate of a word is its box plus the padding', (
      tester,
    ) async {
      final h = await openOne(tester, 'alpha beta gamma');
      h.engine.highlight(
        _words({
          HighlightKind.lookedUp: {'beta'},
        }),
      );
      await tester.pump();

      final result = plates(tester);
      expect(result, hasLength(1));
      expect(result.single.color, h.color(HighlightKind.lookedUp));
      final box = boxes(tester, 6, 10).single;
      expect(result.single.rect, rectMoreOrLessEquals(widened(box)));
      // The plate reaches past the letters, but not by much.
      expect(
        result.single.rect.width,
        box.width + 2 * HighlightPlateShape.horizontalPadding,
      );
    });

    testWidgets('two neighbouring words have two plates, apart', (
      tester,
    ) async {
      final h = await openOne(tester, 'aa bb cc');
      h.engine.highlight(
        _words({
          HighlightKind.lookedUp: {'aa', 'bb'},
        }),
      );
      await tester.pump();

      final result = plates(tester);
      expect(result, hasLength(2));
      expect(result[0].rect.right, lessThan(result[1].rect.left));
      expect(
        result[0].rect,
        rectMoreOrLessEquals(widened(boxes(tester, 0, 2).single)),
      );
      expect(
        result[1].rect,
        rectMoreOrLessEquals(widened(boxes(tester, 3, 5).single)),
      );
    });

    testWidgets('a phrase over a line break has a plate on each line', (
      tester,
    ) async {
      final h = await openOne(tester, 'aaaa bbbb cccc dddd');
      const text = 'aaaa bbbb cccc dddd';
      h.engine.highlight(
        ReaderHighlights(
          ranges: {
            HighlightKind.focus: [_at(h, text, 'bbbb cccc')],
          },
        ),
      );
      await tester.pump();

      final result = plates(tester);
      final expected = boxes(tester, 5, 14);
      expect(expected, hasLength(2));
      expect(result, hasLength(2));
      expect(result[0].rect, rectMoreOrLessEquals(widened(expected[0])));
      expect(result[1].rect, rectMoreOrLessEquals(widened(expected[1])));
      expect(result[0].rect.bottom, lessThan(result[1].rect.top));
      expect(marksOf(tester, find.byType(SelectableText)), [
        ('bbbb cccc', h.color(HighlightKind.focus)),
      ]);
    });

    testWidgets('the text lays out the same with and without plates', (
      tester,
    ) async {
      final h = await openOne(tester, 'aaaa bbbb cccc dddd eeee ffff');
      final selectable = find.byType(SelectableText);
      EditableTextState state() =>
          tester.state<EditableTextState>(find.byType(EditableText));
      List<Rect> lines() => [
        for (final box in state().renderEditable.getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 29),
        ))
          box.toRect(),
      ];

      final size = tester.getSize(selectable);
      final before = lines();
      expect(before.length, greaterThan(2));

      h.engine.highlight(
        _words({
          HighlightKind.difficult: {'bbbb', 'cccc', 'eeee'},
          HighlightKind.focus: {'dddd'},
        }),
      );
      await tester.pump();
      expect(plates(tester), isNotEmpty);

      expect(tester.getSize(selectable), size);
      expect(lines(), before);
    });

    testWidgets('the line height does not move the plate off the letters', (
      tester,
    ) async {
      final h = await openOne(tester, 'alpha beta gamma');
      h.engine.highlight(
        _words({
          HighlightKind.lookedUp: {'beta'},
        }),
      );
      // Line heights where the plate is not cut by its line. Where the plate
      // is against the letters: its top and bottom measured
      // from the baseline (even leading, as in `widened`).
      final placed = <(double, double)>[];
      for (final lineHeight in [1.5, 2.0, 2.5]) {
        h.engine.applySettings(ReaderSettings(lineHeight: lineHeight));
        await tester.pump();
        final box = boxes(tester, 6, 10).single;
        final plate = plates(tester).single.rect;
        final baseline = box.bottom - (box.height - 18) / 2 - 18 * 0.25;
        placed.add((plate.top - baseline, plate.bottom - baseline));
      }
      for (final (top, bottom) in placed.skip(1)) {
        expect(top, moreOrLessEquals(placed.first.$1, epsilon: 0.01));
        expect(bottom, moreOrLessEquals(placed.first.$2, epsilon: 0.01));
      }
    });

    testWidgets('the plate sits on the baseline the same way for both '
        'leading distributions', (tester) async {
      // Where the plate is against the real baseline of the first line.
      Future<(double, double)> place(
        double lineHeight,
        TextLeadingDistribution leading,
      ) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: HighlightPlates(
                ranges: const [
                  (start: 0, end: 5, color: Color(0xFF000000), pulse: false),
                ],
                child: SelectableText(
                  'alpha beta',
                  style: TextStyle(
                    fontSize: 20,
                    height: lineHeight,
                    leadingDistribution: leading,
                  ),
                ),
              ),
            ),
          ),
        );
        final editable = tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;
        final baseline = editable
            .localToGlobal(
              Offset(
                0,
                editable.computeDistanceToActualBaseline(
                  TextBaseline.alphabetic,
                ),
              ),
            )
            .dy;
        final plate = tester
            .renderObject<RenderHighlightPlates>(find.byType(HighlightPlates))
            .plates
            .single
            .rect;
        return (plate.top - baseline, plate.bottom - baseline);
      }

      final first = await place(1.5, TextLeadingDistribution.proportional);
      for (final (lineHeight, leading) in [
        (2.0, TextLeadingDistribution.proportional),
        (1.5, TextLeadingDistribution.even),
        (2.0, TextLeadingDistribution.even),
      ]) {
        final (top, bottom) = await place(lineHeight, leading);
        expect(top, moreOrLessEquals(first.$1, epsilon: 0.01));
        expect(bottom, moreOrLessEquals(first.$2, epsilon: 0.01));
      }
    });

    for (final lineHeight in [1.0, 1.5, 2.5]) {
      testWidgets('plates of two lines do not overlap at line height '
          '$lineHeight', (tester) async {
        final h = await openOne(tester, 'aaaa bbbb cccc dddd eeee ffff');
        h.engine.applySettings(ReaderSettings(lineHeight: lineHeight));
        await tester.pump();
        h.engine.highlight(
          ReaderHighlights(
            ranges: {
              HighlightKind.focus: [
                _at(h, 'aaaa bbbb cccc dddd eeee ffff', 'bbbb cccc dddd eeee'),
              ],
            },
          ),
        );
        await tester.pump();

        final result = plates(tester);
        expect(result.length, greaterThanOrEqualTo(3));
        for (var i = 0; i + 1 < result.length; i++) {
          expect(result[i].rect.bottom, lessThan(result[i + 1].rect.top));
        }
      });
    }

    testWidgets('a plate is painted rounded, under the text', (tester) async {
      final h = await openOne(tester, 'alpha beta gamma');
      h.engine.highlight(
        _words({
          HighlightKind.lookedUp: {'beta'},
        }),
      );
      await tester.pump();

      final plate = plates(tester).single;
      expect(
        tester.renderObject(find.byType(HighlightPlates)),
        paints
          ..rrect(
            rrect: RRect.fromRectAndRadius(plate.rect, radius),
            color: plate.color,
          )
          ..paragraph(),
      );
    });
  });

  group('cost', () {
    // Counts the rebuilds of the block views while [body] runs.
    Future<List<int>> rebuilt(Future<void> Function() body) async {
      final blocks = <int>[];
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        final widget = element.widget;
        if (widget is BlockView) blocks.add(widget.index);
      };
      try {
        await body();
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      return blocks..sort();
    }

    testWidgets('only the blocks whose marks change are rebuilt', (
      tester,
    ) async {
      final h = await _open(tester, [
        'alpha beta',
        'gamma delta',
        'alpha again',
        'nothing here',
      ]);

      final first = await rebuilt(() async {
        h.engine.highlight(
          _words({
            HighlightKind.lookedUp: {'alpha'},
          }),
        );
        await tester.pump();
      });
      expect(first, [0, 2]);

      final second = await rebuilt(() async {
        h.engine.highlight(
          _words({
            HighlightKind.lookedUp: {'alpha'},
            HighlightKind.recent: {'delta'},
          }),
        );
        await tester.pump();
      });
      expect(second, [1]);

      final same = await rebuilt(() async {
        h.engine.highlight(
          _words({
            HighlightKind.recent: {'delta'},
            HighlightKind.lookedUp: {'alpha'},
          }),
        );
        await tester.pump();
      });
      expect(same, isEmpty);

      final cleared = await rebuilt(() async {
        h.engine.highlight(ReaderHighlights.none);
        await tester.pump();
      });
      expect(cleared, [0, 1, 2]);
    });

    testWidgets('a change of the style rebuilds the blocks', (tester) async {
      final h = await _open(tester, ['alpha beta', 'gamma delta']);
      final blocks = await rebuilt(() async {
        h.engine.applySettings(const ReaderSettings(fontSize: 20));
        await tester.pump();
      });
      expect(blocks, [0, 1]);
    });

    testWidgets('lemmas are computed once per chapter', (tester) async {
      final h = await _open(tester, paragraphs);
      expect(h.analyzer.lemmaCalls, 0);

      h.engine.highlight(
        _words({
          HighlightKind.lookedUp: {'run'},
        }),
      );
      await tester.pump();
      final once = h.analyzer.lemmaCalls;
      expect(once, greaterThan(0));

      h.engine.highlight(
        _words({
          HighlightKind.difficult: {'dog', 'fun'},
        }),
      );
      await tester.pump();
      h.engine.highlight(ReaderHighlights.none);
      await tester.pump();
      h.engine.highlight(
        _words({
          HighlightKind.recent: {'see'},
        }),
      );
      await tester.pump();
      expect(h.analyzer.lemmaCalls, once);
    });

    testWidgets('a place alone does not lemmatize anything', (tester) async {
      final h = await _open(tester, paragraphs);
      final text = paragraphs.join('\n\n');
      h.engine.highlight(
        ReaderHighlights(
          ranges: {
            HighlightKind.focus: [_at(h, text, 'dog')],
          },
        ),
      );
      await tester.pump();
      expect(h.analyzer.lemmaCalls, 0);
    });

    testWidgets('300 lemmas in a 15 000-word chapter take under 50 ms', (
      tester,
    ) async {
      // Words w0..w14999, 30 to a paragraph. The 300 marked lemmas are w0..w59
      // (in the first two paragraphs, on screen) and w7000..w7239 (far away).
      final text = [
        for (var p = 0; p < 500; p++)
          [for (var i = 0; i < 30; i++) 'w${p * 30 + i}'].join(' '),
      ];
      final h = await _open(tester, text);
      final highlights = _words({
        HighlightKind.difficult: {
          for (var i = 0; i < 60; i++) 'w$i',
          for (var i = 7000; i < 7240; i++) 'w$i',
        },
      });

      final visible = find.byType(BlockView).evaluate().length;
      expect(visible, greaterThan(2));

      final watch = Stopwatch()..start();
      final blocks = await rebuilt(() async {
        h.engine.highlight(highlights);
        await tester.pump();
      });
      watch.stop();

      expect(watch.elapsedMilliseconds, lessThan(50));
      // Only the two paragraphs with marked words on screen changed.
      expect(blocks, [0, 1]);
      expect(allMarks(tester).length, 60);
    });
  });
}
