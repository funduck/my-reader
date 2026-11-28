import 'package:core/domain_books.dart';
import 'package:core_testing/core_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_api/reader_api.dart';
import 'package:reader_simple/reader_simple.dart';
import 'package:reader_simple/src/block_view.dart';
import 'package:reader_simple/src/highlight_plates.dart';
import 'package:reader_simple/src/highlight_pulse.dart';

import 'fake_text_analyzer.dart';
import 'plate_marks.dart';

const _bookId = BookId('book-1');
const _paragraphs = ['She runs fast.', 'The dog sleeps. A cat wakes.'];

ReaderHighlights _recent(String lemma, [Set<String> looked = const {}]) =>
    ReaderHighlights(
      words: {
        HighlightKind.recent: {lemma},
        if (looked.isNotEmpty) HighlightKind.lookedUp: looked,
      },
    );

Future<SimpleReaderEngine> _open(
  WidgetTester tester, {
  bool reduceMotion = false,
}) async {
  final engine = SimpleReaderEngine(analyzer: FakeTextAnalyzer());
  addTearDown(engine.dispose);
  await engine.load(
    FakeOpenedBook(chapters: [_paragraphs.join('\n\n')]),
    bookId: _bookId,
  );
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: Scaffold(body: Builder(builder: engine.buildView)),
    ),
  );
  await tester.pump();
  return engine;
}

/// Gives the engine [highlights] and shows two frames, the second of which is
/// the first tick of a pulse that has started (a ticker counts from its first
/// frame).
Future<void> _highlight(
  WidgetTester tester,
  SimpleReaderEngine engine,
  ReaderHighlights highlights,
) async {
  engine.highlight(highlights);
  await tester.pump();
  await tester.pump();
}

/// The plates of every paragraph on screen.
List<Plate> _plates(WidgetTester tester) => [
  for (var i = 0; i < find.byType(SelectableText).evaluate().length; i++)
    ...platesOf(tester, find.byType(SelectableText).at(i)),
];

/// The opacity of the one plate that pulses, or `null` when it is not drawn,
/// sampled every [step] for [total].
Future<List<double?>> _sample(
  WidgetTester tester, {
  Duration step = const Duration(milliseconds: 50),
  Duration total = recentPulseDuration,
}) async {
  final result = <double?>[];
  for (var at = Duration.zero; at < total; at += step) {
    await tester.pump(step);
    final plates = _plates(tester);
    result.add(plates.isEmpty ? null : plates.single.opacity);
  }
  return result;
}

/// How many times the series rises and then falls.
int _peaks(List<double?> series) {
  var peaks = 0;
  var rising = false;
  double? last;
  for (final value in series.whereType<double>()) {
    if (last != null) {
      if (value > last + 1e-9) {
        rising = true;
      } else if (value < last - 1e-9) {
        if (rising) peaks++;
        rising = false;
      }
    }
    last = value;
  }
  return peaks;
}

void main() {
  group('recentPulseOpacity', () {
    test('two pulses, then the fade; exactly 0 at the end', () {
      final series = [
        for (var i = 0; i <= 100; i++)
          recentPulseOpacity(i / 100, reduceMotion: false),
      ];
      expect(series.first, 0);
      expect(series.last, 0);
      expect(series.reduce((a, b) => a > b ? a : b), 1);
      expect(_peaks(series), 2);
      expect(series.every((v) => v >= 0 && v <= 1), isTrue);
    });

    test('reduce motion: steady, then the fade, no oscillation', () {
      final series = [
        for (var i = 0; i <= 100; i++)
          recentPulseOpacity(i / 100, reduceMotion: true),
      ];
      expect(series.first, 1);
      expect(series.last, 0);
      for (var i = 1; i < series.length; i++) {
        expect(series[i], lessThanOrEqualTo(series[i - 1]));
      }
    });

    test('past the end it stays 0', () {
      expect(recentPulseOpacity(1.5, reduceMotion: false), 0);
      expect(recentPulseOpacity(1.5, reduceMotion: true), 0);
    });
  });

  group('the pulse of a recent mark', () {
    testWidgets('the plate rises and falls twice, then it is gone', (
      tester,
    ) async {
      final engine = await _open(tester);
      await _highlight(tester, engine, _recent('dog'));
      expect(_plates(tester).single.opacity, 0);

      final series = await _sample(
        tester,
        step: const Duration(milliseconds: 25),
      );
      final drawn = series.whereType<double>();
      expect(drawn.reduce((a, b) => a > b ? a : b), closeTo(1, 0.15));
      expect(_peaks(series), 2);
      // Between the pulses the plate dims but stays.
      expect(
        series.whereType<double>().where((v) => v > 0.2 && v < 0.4),
        isNotEmpty,
      );

      // At 2.5 s there is no plate, and none comes back.
      expect(_plates(tester), isEmpty);
      await tester.pump(const Duration(seconds: 10));
      expect(_plates(tester), isEmpty);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('the plate is painted with the opacity of the pulse', (
      tester,
    ) async {
      final engine = await _open(tester);
      final color = engine.style.value
          .highlightOf(HighlightKind.recent)
          .background!;
      await _highlight(tester, engine, _recent('dog'));
      // 10 % of 2.5 s: full.
      await tester.pump(const Duration(milliseconds: 250));
      final plate = _plates(tester).single;
      expect(plate.opacity, closeTo(1, 1e-6));
      expect(
        tester.renderObject(find.byType(HighlightPlates).last),
        paints..rrect(color: color),
      );
      // 35 %: dimmed to 30 % of the colour.
      await tester.pump(const Duration(milliseconds: 625));
      expect(_plates(tester).single.opacity, closeTo(0.3, 1e-6));
      expect(
        tester.renderObject(find.byType(HighlightPlates).last),
        paints..rrect(color: color.withValues(alpha: color.a * 0.3)),
      );
    });

    testWidgets('reduce motion: steady, no oscillation, gone at 2.5 s', (
      tester,
    ) async {
      final engine = await _open(tester, reduceMotion: true);
      await _highlight(tester, engine, _recent('dog'));
      expect(_plates(tester).single.opacity, 1);

      final series = await _sample(tester);
      final drawn = series.whereType<double>().toList();
      expect(drawn.first, 1);
      for (var i = 1; i < drawn.length; i++) {
        expect(drawn[i], lessThanOrEqualTo(drawn[i - 1]));
      }
      expect(_peaks(series), 0);
      expect(_plates(tester), isEmpty);
    });

    testWidgets('a new recent mark cuts the old pulse short', (tester) async {
      final engine = await _open(tester);
      await _highlight(tester, engine, _recent('dog'));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(_plates(tester), hasLength(1));

      await _highlight(tester, engine, _recent('cat'));
      await tester.pump(const Duration(milliseconds: 250));
      final text = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((w) => w.textSpan!.toPlainText())
          .join();
      expect(text, contains('dog'));
      expect(allMarks(tester).map((m) => m.$1), ['cat']);
      // The new pulse starts from its start: full at 10 %.
      expect(_plates(tester).single.opacity, closeTo(1, 1e-6));

      // The old pulse would have ended 1 s after the new mark; the new one
      // goes on until 2.5 s.
      await tester.pump(const Duration(milliseconds: 950));
      expect(_plates(tester), hasLength(1));
      await tester.pump(const Duration(milliseconds: 1300));
      expect(_plates(tester), isEmpty);
    });

    testWidgets('the same recent mark again does not restart the pulse', (
      tester,
    ) async {
      final engine = await _open(tester);
      await _highlight(tester, engine, _recent('dog'));
      await tester.pump(const Duration(seconds: 1));

      // Another kind comes and goes; `recent` is as it was.
      engine
        ..highlight(_recent('dog', {'cat'}))
        ..highlight(_recent('dog'));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(_plates(tester), isEmpty);
    });

    testWidgets('taking the mark off stops the pulse at once', (tester) async {
      final engine = await _open(tester);
      // Frame callbacks the view has without a pulse.
      final idle = tester.binding.transientCallbackCount;
      await _highlight(tester, engine, _recent('dog'));
      expect(tester.binding.transientCallbackCount, greaterThan(idle));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_plates(tester), hasLength(1));

      engine.highlight(ReaderHighlights.none);
      await tester.pump();
      expect(_plates(tester), isEmpty);
      expect(tester.binding.transientCallbackCount, idle);

      // The same word later pulses again from the start.
      await _highlight(tester, engine, _recent('dog'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(_plates(tester).single.opacity, closeTo(1, 1e-6));
    });

    testWidgets('other kinds are steady while a mark pulses', (tester) async {
      final engine = await _open(tester);
      await _highlight(tester, engine, _recent('dog', {'cat'}));
      final blue = engine.style.value
          .highlightOf(HighlightKind.lookedUp)
          .background;
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 400));
        final looked = _plates(tester).where((p) => p.color == blue);
        expect(looked.map((p) => p.opacity), [1]);
      }
    });

    testWidgets('a frame of the pulse repaints, it rebuilds no block', (
      tester,
    ) async {
      final engine = await _open(tester);
      await _highlight(tester, engine, _recent('dog'));

      final rebuilt = <int>[];
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        final widget = element.widget;
        if (widget is BlockView) rebuilt.add(widget.index);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      for (var i = 0; i < 26; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(rebuilt, isEmpty);
      expect(_plates(tester), isEmpty);
    });

    testWidgets('the view goes away mid-pulse without a running ticker', (
      tester,
    ) async {
      final engine = await _open(tester);
      await _highlight(tester, engine, _recent('dog'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(const SizedBox());
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
