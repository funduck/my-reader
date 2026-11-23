import 'dart:async';

import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup_sheet/lookup_sheet.dart';
import 'package:my_reader_app/bootstrap.dart';
import 'package:reader_api/reader_api.dart';

import 'support/lookup_e2e.dart';

class _FakeEngine implements ReaderEngine {
  final _events = StreamController<ReaderEvent>.broadcast();

  void emit(ReaderEvent event) => _events.add(event);

  @override
  Widget buildView(BuildContext context) => const Text(fixtureParagraph);

  @override
  Future<void> load(
    OpenedBook book, {
    required BookId bookId,
    Locator? at,
  }) async {}

  @override
  Future<void> goTo(Locator locator) async {}

  @override
  void applySettings(ReaderSettings settings) {}

  @override
  void highlight(List<Locator> ranges) {}

  @override
  Stream<ReaderEvent> get events => _events.stream;

  @override
  Future<void> dispose() => _events.close();
}

/// The same scenario as `integration_test/lookup_e2e_test.dart`, with a fake
/// engine that reports the tap, and without the latency check: the fake clock
/// of the test does not measure it.
void main() {
  Locator at(double progression) => Locator(
    book: fixtureBookId,
    chapter: const ChapterRef(href: 'chapter1.xhtml', index: 0),
    progression: progression,
    quote: const TextQuote(exact: 'Child'),
  );

  testWidgets('tap -> sheet -> journal and term; second tap counts again; '
      'offline', (tester) async {
    final fixture = await LookupFixture.create();
    final engine = _FakeEngine();
    await tester.pumpWidget(
      bootstrap(overrides: fixture.overrides(engine: () => engine)),
    );

    // Drift and sqlite finish outside the fake-async zone.
    Future<void> settle([bool Function()? done]) async {
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (done != null && done()) return;
      }
      if (done != null) fail('the condition did not come true');
    }

    bool shown() =>
        find.textContaining(fixtureDefinition).evaluate().isNotEmpty;

    await settle(() => find.byType(Text).evaluate().isNotEmpty);

    // An accidental tap: the sheet is closed before the threshold, so the
    // lookup reaches neither the journal nor the term (T-086).
    engine.emit(
      WordTapped(word: 'Child', at: at(0.05), sentence: fixtureParagraph),
    );
    await settle(shown);
    await tester.pump(
      minLookupViewDuration - const Duration(milliseconds: 500),
    );
    await tester.tapAt(const Offset(10, 10));
    await settle(() => !shown());
    await tester.pump(const Duration(seconds: 5));
    await settle();
    expect(await tester.runAsync(() => journalOf(fixture)), isEmpty);
    expect(await tester.runAsync(() => termsOf(fixture)), isEmpty);

    for (final taps in [1, 2]) {
      engine.emit(
        WordTapped(
          word: 'Child',
          at: at(0.1 * taps),
          sentence: fixtureParagraph,
        ),
      );
      await settle();
      await settle(shown);
      expect(find.textContaining(fixtureDefinition), findsOneWidget);
      // Written after the result has been on screen for 2 s.
      await tester.pump(minLookupViewDuration);
      await settle();
      final events = await tester.runAsync(() => journalOf(fixture));
      expect(events!.first.query.locator, at(0.1 * taps));
      final terms = await tester.runAsync(() => termsOf(fixture));
      expect(terms!.single.lookupCount, taps);

      // Close the sheet: tap on the scrim above it.
      await tester.tapAt(const Offset(10, 10));
      await settle(() => !shown());
      expect(find.textContaining(fixtureDefinition), findsNothing);
    }

    await tester.runAsync(
      () => expectLookups(fixture, taps: 2, sentence: fixtureParagraph),
    );

    // Unmount; drift cancels its streams on a zero-duration timer. The
    // database is not closed: closing inside runAsync hangs.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
