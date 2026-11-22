import 'package:core/domain_books.dart';
import 'package:core_testing/core_testing.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_simple/reader_simple.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// Frame budget from the T-021 spike report (spikes/reader/REPORT.md,
/// section 3): p99 of build and raster must stay within one 60 Hz frame.
/// The spike measured p99 build 2.87 ms and raster 1.75 ms on the same kind
/// of chapter; the threshold is the report's 16 ms.
const _budget = Duration(milliseconds: 16);

const _words =
    'the quick brown fox jumps over a lazy dog while reading an old book '
    'about distant harbours quiet mornings and long winding roads home';

/// A chapter of exactly 15 000 words: 150 paragraphs of 100 words.
String chapterOf15kWords() {
  final vocabulary = _words.split(' ');
  final paragraphs = <String>[];
  var next = 0;
  for (var p = 0; p < 150; p++) {
    final words = <String>[];
    for (var w = 0; w < 100; w++) {
      words.add(vocabulary[next++ % vocabulary.length]);
    }
    paragraphs.add(words.join(' '));
  }
  return paragraphs.join('\n\n');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    // Draw every frame the framework asks for, as on a real screen; by
    // default only pumped frames are drawn.
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('scrolling a 15 000-word chapter stays within the budget', (
    tester,
  ) async {
    final text = chapterOf15kWords();
    expect(text.split(RegExp(r'\s+')).length, 15000);

    final engine = SimpleReaderEngine();
    addTearDown(engine.dispose);
    await engine.load(
      FakeOpenedBook(chapters: [text]),
      bookId: const BookId('perf'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: engine.buildView)),
      ),
    );
    await tester.pumpAndSettle();
    final list = find.byType(ScrollablePositionedList);

    // The timeline of traceAction is a ring buffer in profile mode and keeps
    // only the last ~70 frames of a long run (see the spike report), so the
    // verdict is computed from the engine's FrameTiming of every frame.
    final timings = <FrameTiming>[];
    void onTimings(List<FrameTiming> t) => timings.addAll(t);
    SchedulerBinding.instance.addTimingsCallback(onTimings);

    var distance = 0.0;
    double pixels() => tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .map((s) => s.position.pixels)
        .reduce((a, b) => a > b ? a : b);

    Future<void> fling(double dy) async {
      final before = pixels();
      await tester.fling(list, Offset(0, dy), 2500);
      await tester.pumpAndSettle();
      distance += (pixels() - before).abs();
    }

    await binding.traceAction(() async {
      for (var i = 0; i < 40; i++) {
        await fling(-700);
      }
      for (var i = 0; i < 20; i++) {
        await fling(700);
      }
      // Timings arrive in batches; let the last batch in.
      await tester.pump(const Duration(seconds: 1));
    }, reportKey: 'scroll_timeline');
    SchedulerBinding.instance.removeTimingsCallback(onTimings);

    final summary = FrameTimingSummarizer(timings);
    String ms(Duration d) => (d.inMicroseconds / 1000).toStringAsFixed(2);
    // The numbers go to the README of the package.
    debugPrint(
      'FRAMES all: ${timings.length}, scrolled px: ${distance.round()}\n'
      'FRAMES p99 build ${ms(summary.p99FrameBuildTime)} ms, '
      'raster ${ms(summary.p99FrameRasterizerTime)} ms\n'
      'FRAMES worst build ${ms(summary.worstFrameBuildTime)} ms, '
      'raster ${ms(summary.worstFrameRasterizerTime)} ms\n'
      'FRAMES missed budget: build ${summary.missedFrameBuildBudget}, '
      'raster ${summary.missedFrameRasterizerBudget}',
    );

    expect(distance, greaterThan(60 * 500), reason: 'flings did not scroll');
    expect(timings.length, greaterThan(1000), reason: 'too few frames drawn');
    expect(summary.p99FrameBuildTime, lessThanOrEqualTo(_budget));
    expect(summary.p99FrameRasterizerTime, lessThanOrEqualTo(_budget));
  });
}
