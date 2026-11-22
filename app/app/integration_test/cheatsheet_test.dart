import 'dart:io';

import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:my_reader_app/bootstrap.dart';
import 'package:my_reader_app/router.dart';
import 'package:reader_simple/reader_simple.dart';
import 'package:text_en/text_en.dart';

/// Mini `en-levels` pack of the service fixtures (`ephemeral` is C2,
/// `ubiquitous` C1, `cat` A1). The path is relative to `app/app`, where
/// `flutter test integration_test -d macos` runs.
const _levelsFixture =
    '../../service/fixtures/packs/en-levels-20260101.1.sqlite';

/// Runs on macOS by a human (`flutter test integration_test/cheatsheet_test.dart
/// -d macos`): book -> "Разминка" -> words -> tap -> definition, with the real
/// analyzer, level dictionary, generator, reader and lookup sheet. The same
/// scenario with the 1 second limit is in `test/cheatsheet_wiring_test.dart`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const id = BookId('b1');
  const pid = ProviderId('fake.dict');

  testWidgets('book -> "Разминка" -> words -> tap -> definition', (
    tester,
  ) async {
    final packs = Directory.systemTemp.createTempSync('my-reader-packs');
    addTearDown(() => packs.deleteSync(recursive: true));
    File(_levelsFixture).copySync('${packs.path}/en-levels.sqlite');

    final books = FakeBookRepository();
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
    final adapter = FakeBookFormatAdapter()
      ..register(
        '/x/b1.epub',
        const BookMetadata(title: 'Dune'),
        chapters: ['The ephemeral light was ubiquitous. A cat sat.'],
      );
    final dictionary = FakeLookupProvider(
      id: pid,
      answers: const {
        'ephemeral': LookupResult(
          provider: pid,
          senses: [Sense(text: 'lasting a very short time')],
        ),
      },
    );

    await tester.pumpWidget(
      bootstrap(
        overrides: [
          ...buildOverrides(),
          ...buildLookupOverrides(packs.path, providers: (_) => [dictionary]),
          bookRepositoryProvider.overrideWithValue(books),
          progressRepositoryProvider.overrideWithValue(
            FakeProgressRepository(),
          ),
          profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
          bookFormatsProvider.overrideWithValue([adapter]),
          lookupJournalProvider.overrideWithValue(FakeLookupJournal()),
          termRepositoryProvider.overrideWithValue(FakeTermRepository()),
          readerEngineFactoryProvider.overrideWithValue(
            () => SimpleReaderEngine(analyzer: const EnglishTextAnalyzer()),
          ),
          routerProvider.overrideWith(
            (ref) => createRouter(initialLocation: Routes.readerAt('b1')),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Разминка'));
    await tester.pumpAndSettle();

    expect(find.text('Не удалось подготовить разминку.'), findsNothing);
    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.text('ubiquitous'), findsOneWidget);
    expect(find.text('cat'), findsNothing);

    await tester.tap(find.text('ephemeral'));
    await tester.pumpAndSettle();
    expect(find.text('1. lasting a very short time'), findsOneWidget);
  });
}
