import 'dart:async';
import 'dart:io';

import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:my_reader_app/bootstrap.dart';
import 'package:reader_api/reader_api.dart';
import 'package:reader_simple/reader_simple.dart';
import 'package:text_en/text_en.dart';

import '../test/support/lookup_e2e.dart';

/// Path of the real `en-en` pack for the U-3 run: the environment variable or
/// `--dart-define=EN_EN_PACK=...`. Empty when not set.
const _definedPack = String.fromEnvironment('EN_EN_PACK');
final String _enEnPack = _definedPack.isNotEmpty
    ? _definedPack
    : (Platform.environment['EN_EN_PACK'] ?? '');

/// The latency limit of a lookup: from the tap that the engine reports to the
/// frame with the definition.
const _limit = Duration(milliseconds: 300);

/// The real engine that tells when it reported a tap.
///
/// `SimpleReaderEngine` reports a tap `kDoubleTapTimeout` (300 ms) after the
/// finger, on purpose: a double click is a selection, not a tap. That wait is
/// not the lookup, so the stopwatch starts when the event leaves the engine.
class _TimedEngine implements ReaderEngine {
  new(this.onTap)
    : _inner = SimpleReaderEngine(analyzer: const EnglishTextAnalyzer());

  final void Function() onTap;
  final ReaderEngine _inner;

  @override
  Widget buildView(BuildContext context) => _inner.buildView(context);

  @override
  Future<void> load(OpenedBook book, {required BookId bookId, Locator? at}) =>
      _inner.load(book, bookId: bookId, at: at);

  @override
  Future<void> goTo(Locator locator) => _inner.goTo(locator);

  @override
  void applySettings(ReaderSettings settings) => _inner.applySettings(settings);

  @override
  void highlight(List<Locator> ranges) => _inner.highlight(ranges);

  @override
  Stream<ReaderEvent> get events => _inner.events.map((event) {
    if (event is WordTapped) onTap();
    return event;
  });

  @override
  Future<void> dispose() => _inner.dispose();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Taps the first word of the paragraph, closes nothing; returns the time
  /// from the engine's tap event to the frame where [shown] finds a widget,
  /// and from the finger to that frame.
  Future<({Duration lookup, Duration total})> tapAndWait(
    WidgetTester tester,
    Stopwatch eventWatch,
    Finder shown,
  ) async {
    final total = Stopwatch()..start();
    eventWatch
      ..stop()
      ..reset();
    final word = find.textContaining('Child', findRichText: true).first;
    await tester.tapAt(tester.getTopLeft(word) + const Offset(6, 10));
    // The engine reports the tap after the double-tap timeout.
    while (!eventWatch.isRunning) {
      await tester.pump(const Duration(milliseconds: 10));
      if (total.elapsed > const Duration(seconds: 5)) fail('no tap event');
    }
    while (shown.evaluate().isEmpty) {
      await tester.pump();
      if (eventWatch.elapsed > const Duration(seconds: 5)) {
        fail('no definition in 5 s');
      }
    }
    eventWatch.stop();
    total.stop();
    return (lookup: eventWatch.elapsed, total: total.elapsed);
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  }

  testWidgets('tap -> definition offline -> journal and term; recount; '
      'under 300 ms on the mini pack', (tester) async {
    final fixture = await LookupFixture.create();
    addTearDown(fixture.database.close);
    final eventWatch = Stopwatch();
    await tester.pumpWidget(
      bootstrap(
        overrides: fixture.overrides(
          engine: () => _TimedEngine(eventWatch.start),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final definition = find.textContaining(fixtureDefinition);
    final first = await tapAndWait(tester, eventWatch, definition);
    debugPrint(
      'mini pack: event to frame ${first.lookup.inMilliseconds} ms, '
      'finger to frame ${first.total.inMilliseconds} ms',
    );
    expect(first.lookup, lessThan(_limit));
    await tester.pumpAndSettle();

    final events = await journalOf(fixture);
    final locator = events.single.query.locator!;
    expect(locator.book, fixtureBookId);
    expect(locator.quote?.exact, 'Child');
    expect(events.single.query.sentence, fixtureParagraph);
    expect((await termsOf(fixture)).single.lookupCount, 1);

    await closeSheet(tester);
    final second = await tapAndWait(tester, eventWatch, definition);
    expect(second.lookup, lessThan(_limit));
    await tester.pumpAndSettle();
    await expectLookups(fixture, taps: 2, sentence: fixtureParagraph);
  });

  testWidgets('real en-en pack: lookup under 300 ms', (tester) async {
    final fixture = await LookupFixture.create(enEnFile: _enEnPack);
    addTearDown(fixture.database.close);
    final eventWatch = Stopwatch();
    await tester.pumpWidget(
      bootstrap(
        overrides: fixture.overrides(
          engine: () => _TimedEngine(eventWatch.start),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Any numbered sense: the sheet left the skeleton and has an answer.
    final answer = find.textContaining(RegExp(r'^1\. '));
    final result = await tapAndWait(tester, eventWatch, answer);
    debugPrint(
      'real en-en: event to frame ${result.lookup.inMilliseconds} ms, '
      'finger to frame ${result.total.inMilliseconds} ms',
    );
    expect(result.lookup, lessThan(_limit));
    expect(fixture.client.attempts, isEmpty);
  }, skip: _enEnPack.isEmpty);
}
