import 'package:core/domain_books.dart';
import 'package:core_testing/core_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_api/reader_api.dart';
import 'package:reader_simple/reader_simple.dart';
import 'package:reader_simple/src/block_view.dart';
import 'package:reader_simple/src/reader_style.dart';

import 'fake_text_analyzer.dart';

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

/// Every marked piece of the text on screen: its text and background.
List<(String, Color)> _marks(WidgetTester tester) {
  final result = <(String, Color)>[];
  for (final widget in tester.widgetList<SelectableText>(
    find.byType(SelectableText),
  )) {
    // Touching marked pieces of one colour are one mark.
    (String, Color)? open;
    widget.textSpan!.visitChildren((span) {
      final color = span is TextSpan ? span.style?.backgroundColor : null;
      if (color == null) {
        if (open != null) result.add(open!);
        open = null;
      } else if (open != null && open!.$2 == color) {
        open = (open!.$1 + (span as TextSpan).text!, color);
      } else {
        if (open != null) result.add(open!);
        open = ((span as TextSpan).text!, color);
      }
      return true;
    });
    if (open != null) result.add(open!);
  }
  return result;
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
      expect(_marks(tester), [
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
      expect(_marks(tester), [
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
      expect(_marks(tester).map((m) => m.$1), ['to']);
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

      expect(_marks(tester), [
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

      expect(_marks(tester), [
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

      expect(_marks(tester), [
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
      expect(_marks(tester), isNotEmpty);

      h.engine.highlight(ReaderHighlights.none);
      await tester.pump();
      expect(_marks(tester), isEmpty);
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
      expect(_marks(tester).length, 60);
    });
  });
}
