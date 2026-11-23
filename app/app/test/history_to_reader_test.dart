import 'dart:async';

import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_reader_app/bootstrap.dart';
import 'package:my_reader_app/router.dart';
import 'package:reader_api/reader_api.dart';
import 'package:storage_drift/storage_drift.dart';
import 'package:text_en/text_en.dart';

class _Levels implements LevelDictionary {
  @override
  WordLevel levelOf(String lemma, {String? pos}) =>
      const WordLevel(CefrLevel.a1);
}

class _FakeEngine implements ReaderEngine {
  final _events = StreamController<ReaderEvent>.broadcast();
  final List<Locator?> loadedAt = [];
  final List<List<Locator>> highlights = [];

  @override
  Widget buildView(BuildContext context) => const Text('engine view');

  @override
  Future<void> load(
    OpenedBook book, {
    required BookId bookId,
    Locator? at,
  }) async => loadedAt.add(at);

  @override
  Future<void> goTo(Locator locator) async {}

  @override
  void applySettings(ReaderSettings settings) {}

  @override
  void highlight(List<Locator> ranges) => highlights.add(ranges);

  @override
  Stream<ReaderEvent> get events => _events.stream;

  @override
  Future<void> dispose() => _events.close();
}

void main() {
  const id = BookId('b1');
  const place = Locator(
    book: id,
    chapter: ChapterRef(href: 'chapter3.xhtml', index: 2),
    progression: 0.25,
    quote: TextQuote(exact: 'Three'),
  );

  testWidgets('lookup -> history -> tap context -> reader at that place', (
    tester,
  ) async {
    final database = openInMemory();
    final adapter = FakeBookFormatAdapter()
      ..register(
        '/x/b1.epub',
        const BookMetadata(title: 'Dune'),
        chapters: ['One.', 'Two.', 'Three.', 'Four.'],
      );
    await tester.runAsync(
      () => database.bookRepository.save(
        Book(
          id: id,
          metadata: const BookMetadata(title: 'Dune'),
          format: BookFormat.epub,
          filePath: '/x/b1.epub',
          contentHash: 'h',
          addedAt: DateTime.utc(2024),
        ),
      ),
    );

    // The lookup of a word selected at `place`, through the real scenario.
    final profiles = FakeProfileRepository();
    final scenario = LookupSelection(
      chain: ProviderChain(
        providers: [
          FakeLookupProvider(
            id: const ProviderId('fake'),
            answers: {
              'three': const LookupResult(
                provider: ProviderId('fake'),
                senses: [Sense(text: 'the number 3')],
              ),
            },
          ),
        ],
        profiles: profiles,
      ),
      analyzer: const EnglishTextAnalyzer(),
      levels: _Levels(),
      journal: database.lookupJournal,
      terms: database.termRepository,
      profiles: profiles,
      clock: FakeClock(),
      ids: SeqIdGenerator(),
    );
    final outcome = await tester.runAsync(() async {
      final found = await scenario(
        text: 'Three',
        sentence: 'Three apples.',
        locator: place,
      );
      await scenario.record(found);
      return found;
    });
    expect(outcome, isA<LookupAnswered>());

    final engines = <_FakeEngine>[];
    await tester.pumpWidget(
      bootstrap(
        overrides: [
          ...buildOverrides(),
          bookRepositoryProvider.overrideWithValue(database.bookRepository),
          profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
          progressRepositoryProvider.overrideWithValue(
            database.progressRepository,
          ),
          lookupJournalProvider.overrideWithValue(database.lookupJournal),
          termRepositoryProvider.overrideWithValue(database.termRepository),
          bookFormatsProvider.overrideWithValue([adapter]),
          readerEngineFactoryProvider.overrideWithValue(() {
            final engine = _FakeEngine();
            engines.add(engine);
            return engine;
          }),
          routerProvider.overrideWith(
            (ref) => createRouter(initialLocation: Routes.history),
          ),
        ],
      ),
    );
    // Drift queries finish outside the fake-async zone.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('three'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Three apples.'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    expect(find.text('engine view'), findsOneWidget);
    expect(engines, hasLength(1));
    expect(engines.single.loadedAt, [place]);
    expect(engines.single.highlights, [
      [place],
    ]);

    // Unmount so that the reader saves and releases the engine.
    await tester.pumpWidget(const SizedBox());
    // Drift cancels its streams on a zero-duration timer.
    await tester.pump(const Duration(milliseconds: 1));
  });
}
