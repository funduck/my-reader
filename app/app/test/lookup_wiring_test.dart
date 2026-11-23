import 'dart:async';
import 'dart:io';

import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup_sheet/lookup_sheet.dart';
import 'package:my_reader_app/bootstrap.dart';
import 'package:my_reader_app/router.dart';
import 'package:reader_api/reader_api.dart';

class _FakeEngine implements ReaderEngine {
  final _events = StreamController<ReaderEvent>.broadcast();

  void emit(ReaderEvent event) => _events.add(event);

  @override
  Widget buildView(BuildContext context) => const Text('engine view');

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

/// The tap-to-lookup chain of `bootstrap.dart` on fakes of the edges: the
/// engine, the dictionary and the stores. Everything between is the real code:
/// the reader screen, the presenter, `showLookupSheet`, `LookupSelection`.
void main() {
  const id = BookId('b1');
  const pid = ProviderId('fake.dict');
  late FakeLookupJournal journal;
  late FakeLookupProvider dictionary;
  late _FakeEngine engine;

  Locator at(double progression) => Locator(
    book: id,
    chapter: const ChapterRef(href: 'chapter1.xhtml', index: 0),
    progression: progression,
  );

  Future<void> pumpReader(WidgetTester tester) async {
    journal = FakeLookupJournal();
    engine = _FakeEngine();
    dictionary = FakeLookupProvider(
      id: pid,
      answers: const {
        'sand': LookupResult(
          provider: pid,
          senses: [Sense(text: 'loose grains of rock')],
        ),
        'sand moves': LookupResult(
          provider: pid,
          senses: [Sense(text: 'the grains shift')],
        ),
      },
    );
    final books = FakeBookRepository();
    final adapter = FakeBookFormatAdapter()
      ..register(
        '/x/b1.epub',
        const BookMetadata(title: 'Dune'),
        chapters: ['One.'],
      );
    await books.save(
      Book(
        id: id,
        metadata: const BookMetadata(title: 'Dune'),
        format: BookFormat.epub,
        filePath: '/x/b1.epub',
        contentHash: 'h',
        addedAt: DateTime.utc(2024),
      ),
    );
    // No packs there: the lazy lemmatizer and level dictionary stay empty.
    final noPacks = '${Directory.systemTemp.path}/my-reader-no-packs';
    await tester.pumpWidget(
      bootstrap(
        overrides: [
          ...buildOverrides(),
          ...buildLookupOverrides(noPacks, providers: (_) => [dictionary]),
          bookRepositoryProvider.overrideWithValue(books),
          progressRepositoryProvider.overrideWithValue(
            FakeProgressRepository(),
          ),
          profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
          bookFormatsProvider.overrideWithValue([adapter]),
          lookupJournalProvider.overrideWithValue(journal),
          termRepositoryProvider.overrideWithValue(FakeTermRepository()),
          readerEngineFactoryProvider.overrideWithValue(() => engine),
          routerProvider.overrideWith(
            (ref) => createRouter(initialLocation: Routes.readerAt('b1')),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<List<LookupEvent>> recorded(WidgetTester tester) async {
    // Let the lookup finish, keep the sheet open past the threshold of T-086
    // (the lookup is recorded only then), let the journal write finish.
    await tester.pumpAndSettle();
    await tester.pump(minLookupViewDuration);
    await tester.pumpAndSettle();
    final events = await tester.runAsync(() => journal.watch().first);
    return events!;
  }

  testWidgets('a tapped word opens the sheet and lands in the journal', (
    tester,
  ) async {
    await pumpReader(tester);
    engine.emit(
      WordTapped(word: 'sand', at: at(0.25), sentence: 'The sand moves.'),
    );
    final events = await recorded(tester);

    expect(find.text('1. loose grains of rock'), findsOneWidget);
    // The sheet also asks offline providers in the other mode (T-090);
    // count only the calls in the mode the lookup was opened in.
    final mode = events.single.query.mode;
    expect(dictionary.calls.where((q) => q.mode == mode).single.text, 'sand');
    final query = events.single.query;
    expect(query.text, 'sand');
    expect(query.locator, at(0.25));
    expect(query.sentence, 'The sand moves.');
  });

  testWidgets('a selection does the same', (tester) async {
    await pumpReader(tester);
    engine.emit(
      TextSelected(
        text: 'sand moves',
        at: at(0.5),
        sentence: 'The sand moves.',
      ),
    );
    final events = await recorded(tester);

    expect(find.text('1. the grains shift'), findsOneWidget);
    final query = events.single.query;
    expect(query.text, 'sand moves');
    expect(query.locator, at(0.5));
    expect(query.sentence, 'The sand moves.');
  });
}
