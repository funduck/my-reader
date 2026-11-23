import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:my_reader_app/bootstrap.dart';
import 'package:my_reader_app/router.dart';
import 'package:reader_simple/reader_simple.dart';
import 'package:storage_drift/storage_drift.dart';
import 'package:text_en/text_en.dart';

class _Levels implements LevelDictionary {
  @override
  WordLevel levelOf(String lemma, {String? pos}) =>
      const WordLevel(CefrLevel.a1);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const id = BookId('b1');
  const place = Locator(
    book: id,
    chapter: ChapterRef(href: 'chapter3.xhtml', index: 2),
    progression: 0,
    quote: TextQuote(exact: 'Gamma'),
  );

  testWidgets('lookup -> history -> tap context -> the place on screen', (
    tester,
  ) async {
    final database = openInMemory();
    addTearDown(database.close);
    final adapter = FakeBookFormatAdapter()
      ..register(
        '/x/b1.epub',
        const BookMetadata(title: 'Dune'),
        chapters: [
          'Alpha chapter text.',
          'Beta chapter text.',
          'Gamma chapter text.',
          'Delta chapter text.',
        ],
      );
    await database.bookRepository.save(
      Book(
        id: id,
        metadata: const BookMetadata(title: 'Dune'),
        format: BookFormat.epub,
        filePath: '/x/b1.epub',
        contentHash: 'h',
        addedAt: DateTime.utc(2024),
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
              'gamma': const LookupResult(
                provider: ProviderId('fake'),
                senses: [Sense(text: 'a Greek letter')],
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
    await scenario.record(
      await scenario(
        text: 'Gamma',
        sentence: 'Gamma chapter text.',
        locator: place,
      ),
    );

    await tester.pumpWidget(
      bootstrap(
        overrides: [
          ...buildOverrides(),
          bookRepositoryProvider.overrideWithValue(database.bookRepository),
          progressRepositoryProvider.overrideWithValue(
            database.progressRepository,
          ),
          lookupJournalProvider.overrideWithValue(database.lookupJournal),
          termRepositoryProvider.overrideWithValue(database.termRepository),
          bookFormatsProvider.overrideWithValue([adapter]),
          readerEngineFactoryProvider.overrideWithValue(
            () => SimpleReaderEngine(analyzer: const EnglishTextAnalyzer()),
          ),
          routerProvider.overrideWith(
            (ref) => createRouter(initialLocation: Routes.history),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('gamma'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gamma chapter text.'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Gamma chapter text.', findRichText: true),
      findsWidgets,
    );
    expect(find.textContaining('Alpha', findRichText: true), findsNothing);
  });
}
