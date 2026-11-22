import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_spike/main.dart' as app;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

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

    // Frames the framework actually built, and how far the list moved. A
    // headless run gives ~28 frames and ~1600 px per fling; far fewer frames
    // means the window was not drawing (e.g. it was behind other windows).
    var frames = 0;
    var distance = 0.0;
    double pixels() => tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .map((s) => s.position.pixels)
        .reduce((a, b) => a > b ? a : b);
    tester.binding.addPersistentFrameCallback((_) => frames++);

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
    }, reportKey: 'scroll_timeline');

    // ignore: avoid_print
    print(
      'SANITY frames built: $frames, scrolled px: ${distance.round()} '
      '(expect ~1700 frames and ~95000 px for 60 flings)',
    );
    expect(distance, greaterThan(60 * 500), reason: 'flings did not scroll');
  });
}
