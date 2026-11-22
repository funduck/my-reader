import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_spike/main.dart' as app;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// Value at percentile [p] (0..100) of [ms], nearest-rank.
double percentile(List<double> ms, double p) {
  final s = [...ms]..sort();
  final rank = (p / 100 * s.length).ceil().clamp(1, s.length);
  return s[rank - 1];
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    // By default only pumped frames are drawn, so pumpAndSettle advances a
    // fling in 100 ms steps. fullyLive draws every frame the framework asks
    // for, as on a real screen.
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('scroll 15k-word chapter', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    final list = find.byType(ScrollablePositionedList);

    // Frame times come from the engine for every frame. The timeline from
    // traceAction is a ring buffer in profile mode and keeps only the last
    // ~70 frames of a long run, so it is not used for the verdict.
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
      // Timings are delivered in batches; let the last batch arrive.
      await tester.pump(const Duration(seconds: 1));
    }, reportKey: 'scroll_timeline');
    SchedulerBinding.instance.removeTimingsCallback(onTimings);

    double ms(Duration d) => d.inMicroseconds / 1000;
    final build = [for (final t in timings) ms(t.buildDuration)];
    final raster = [for (final t in timings) ms(t.rasterDuration)];
    String f(double v) => v.toStringAsFixed(2);
    // ignore: avoid_print
    print(
      'FRAMES all: ${timings.length}, scrolled px: ${distance.round()}\n'
      'FRAMES p50 build ${f(percentile(build, 50))} ms, '
      'raster ${f(percentile(raster, 50))} ms\n'
      'FRAMES p99 build ${f(percentile(build, 99))} ms, '
      'raster ${f(percentile(raster, 99))} ms\n'
      'FRAMES max build ${f(percentile(build, 100))} ms, '
      'raster ${f(percentile(raster, 100))} ms\n'
      'FRAMES over 16 ms: build ${build.where((v) => v > 16).length}, '
      'raster ${raster.where((v) => v > 16).length}',
    );
    expect(distance, greaterThan(60 * 500), reason: 'flings did not scroll');
    expect(timings.length, greaterThan(1000), reason: 'too few frames drawn');
  });
}
