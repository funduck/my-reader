import 'package:features_cheatsheet/features_cheatsheet.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:my_reader_app/demo/demo_app.dart';
import 'package:my_reader_app/demo/demo_data.dart';
import 'package:my_reader_app/demo/scenarios.dart';

/// Demo app of T-109: every scenario starts on the demo data.
void main() {
  Future<void> settle(WidgetTester tester) async {
    // Part of the loading finishes outside the fake-async zone.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    // Past the lookup sheet's 2 s on screen, so its timer is done.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Finder text(String part) => find.textContaining(part, findRichText: true);

  for (final scenario in demoScenarios) {
    testWidgets('scenario ${scenario.id} starts without errors', (
      tester,
    ) async {
      await tester.pumpWidget(DemoApp(initial: scenario.id));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Demo scenarios'), findsNothing);
      await unmount(tester);
    });
  }

  testWidgets('reader shows the first chapter', (tester) async {
    await tester.pumpWidget(const DemoApp(initial: 'reader'));
    await settle(tester);
    expect(text('Old Tobias lit the lantern'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('lookup_word shows the sheet with the demo translation', (
    tester,
  ) async {
    await tester.pumpWidget(const DemoApp(initial: 'lookup_word'));
    await settle(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('1. фонарь'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('lookup_phrase shows the phrase translation', (tester) async {
    await tester.pumpWidget(const DemoApp(initial: 'lookup_phrase'));
    await settle(tester);
    expect(find.text(demoPhraseTranslation), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('cheatsheet lists a word of the demo levels', (tester) async {
    await tester.pumpWidget(const DemoApp(initial: 'cheatsheet'));
    await settle(tester);
    expect(find.text('mischievous'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the cheat sheet of the demo book lands in the log port', (
    tester,
  ) async {
    await tester.pumpWidget(const DemoApp(initial: 'cheatsheet'));
    await settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CheatSheetScreen)),
    );
    final snapshot = await tester.runAsync(
      () => container.read(cheatSheetLogProvider).watch(demoBookId).first,
    );
    expect(snapshot, isNotNull);
    expect(snapshot!.lemmas, contains('mischievous'));
    await unmount(tester);
  });

  testWidgets('reader_pulse: the word pulses at the start, then it is gone', (
    tester,
  ) async {
    // The plates of the reader are a private widget of `reader_simple`: look
    // at what is painted under the text.
    final plates = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == 'HighlightPlates',
    );
    bool drawn() => plates.evaluate().any((e) => _paintsPlate(e.renderObject!));

    await tester.pumpWidget(const DemoApp(initial: 'reader_pulse'));
    // The book loads outside the fake-async zone; look at every frame until
    // the plate shows (the pulse starts with the list).
    var seen = false;
    for (var i = 0; i < 60 && !seen; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      seen = drawn();
    }
    expect(seen, isTrue);

    // 2.5 s after the first frame it is over.
    await tester.pump(const Duration(seconds: 3));
    expect(drawn(), isFalse);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('without a scenario the list is shown; a tap opens one', (
    tester,
  ) async {
    await tester.pumpWidget(const DemoApp());
    expect(find.text('Demo scenarios'), findsOneWidget);
    await tester.tap(find.text('reader'));
    await settle(tester);
    expect(find.text('Demo scenarios'), findsNothing);
    expect(text('Old Tobias lit the lantern'), findsWidgets);
    await unmount(tester);
  });
}

/// Whether [render] paints a rounded rectangle.
bool _paintsPlate(RenderObject render) {
  try {
    expect(render, paints..rrect());
    return true;
  } on TestFailure {
    return false;
  }
}
