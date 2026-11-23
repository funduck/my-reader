import 'dart:io';

import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_reader_app/bootstrap.dart';
import 'package:my_reader_app/router.dart';
import 'package:reader_simple/reader_simple.dart';
import 'package:text_en/text_en.dart';

/// Mini `en-levels` pack of the service fixtures: `ephemeral` is C2,
/// `fortunate`, `ubiquitous` and `shiny` are C1, `cat` is A1.
const _levelsFixture =
    '../../service/fixtures/packs/en-levels-20260101.1.sqlite';

const _id = BookId('b1');
const _pid = ProviderId('fake.dict');

/// A directory with the `en-levels` pack installed as the app finds it.
Directory _installPacks() {
  final dir = Directory.systemTemp.createTempSync('my-reader-packs');
  addTearDown(() => dir.deleteSync(recursive: true));
  expect(File(_levelsFixture).existsSync(), isTrue, reason: 'fixture missing');
  File(_levelsFixture).copySync('${dir.path}/en-levels.sqlite');
  return dir;
}

Book _book() => Book(
  id: _id,
  metadata: const BookMetadata(title: 'Dune'),
  format: BookFormat.epub,
  filePath: '/x/b1.epub',
  contentHash: 'h',
  addedAt: DateTime.utc(2024),
);

const _filler = [
  'the',
  'old',
  'man',
  'walked',
  'along',
  'a',
  'quiet',
  'road',
  'and',
  'thought',
  'about',
  'his',
  'home',
  'in',
  'cold',
  'weather',
  'while',
  'children',
  'played',
  'near',
  'river',
  'with',
  'small',
  'boats',
  'of',
  'wood',
  'cat',
  'dog',
  'house',
  'water',
  'light',
  'book',
  'green',
  'went',
];

/// [words] words of ordinary text in paragraphs of 30 words; the entries of
/// [rare] (word index -> word) replace the filler at those places.
String _prose(int words, {Map<int, String> rare = const {}}) {
  final out = StringBuffer();
  for (var i = 0; i < words; i++) {
    out.write(rare[i] ?? _filler[(i * 7 + i ~/ 5) % _filler.length]);
    if (i % 30 == 29) {
      out.write('.\n\n');
    } else {
      out.write(i % 10 == 9 ? ', ' : ' ');
    }
  }
  return out.toString();
}

void main() {
  group('the cheat sheet generator of the app wiring', () {
    late FakeProfileRepository profiles;
    late Directory packs;

    setUp(() {
      profiles = FakeProfileRepository();
      packs = _installPacks();
    });

    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: [
          ...buildLookupOverrides(packs.path, providers: (_) => const []),
          profileRepositoryProvider.overrideWithValue(profiles),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    // The use case of the screen over the generator the app provides.
    Future<List<String>> words(
      ProviderContainer c,
      List<String> chapters,
    ) async {
      final sheet =
          await BuildCheatSheet(
            generator: c.read(cheatSheetGeneratorProvider),
            profiles: profiles,
            terms: FakeTermRepository(),
          )(
            FakeOpenedBook(chapters: chapters),
            from: const Locator(
              book: _id,
              chapter: ChapterRef(href: 'chapter1.xhtml', index: 0),
              progression: 0,
            ),
          );
      // The screen picks from all candidates by the profile.
      final profile = await profiles.get();
      return [
        for (final item in selectCheatSheetItems(
          sheet!.items,
          above: profile.level,
          limit: profile.cheatSheetLimit,
        ))
          item.text,
      ];
    }

    test('the level of the profile applies without a restart', () async {
      final chapters = [
        'The ephemeral light was ubiquitous. A fortunate cat sat.',
      ];
      final c = container();

      expect(
        await words(c, chapters),
        unorderedEquals(['ephemeral', 'ubiquitous', 'fortunate']),
      );

      // The same container: the user moves the level up in settings.
      await profiles.save(const UserProfile(level: CefrLevel.c1));
      expect(await words(c, chapters), ['ephemeral']);
    });

    test('the piece size of the profile applies without a restart', () async {
      // `ephemeral` is the 700th word: past 1 page (300), within 10.
      final chapters = [
        _prose(1000, rare: {700: 'ephemeral'}),
      ];
      final c = container();

      await profiles.save(const UserProfile(scope: CheatSheetPages(1)));
      expect(await words(c, chapters), isEmpty);

      await profiles.save(const UserProfile());
      expect(await words(c, chapters), ['ephemeral']);
    });

    test('10 pages (3000 words) are built in under 1 second', () async {
      // The piece is the first 3000 words; the third chapter is not read.
      final chapters = [
        _prose(1500, rare: {100: 'ephemeral', 900: 'ubiquitous'}),
        _prose(1500, rare: {200: 'fortunate', 1400: 'shiny'}),
        _prose(3000, rare: {5: 'polish'}),
      ];
      final c = container();
      expect(
        (await profiles.get()).scope,
        const CheatSheetPages(10),
        reason: 'the default piece is 10 pages',
      );
      // Warm-up: the first call opens the pack file.
      await words(c, chapters);

      // Real time: `test` runs without fake clocks.
      final timer = Stopwatch()..start();
      final found = await words(c, chapters);
      timer.stop();

      expect(
        found,
        unorderedEquals(['ephemeral', 'ubiquitous', 'fortunate', 'shiny']),
      );
      expect(
        timer.elapsedMilliseconds,
        lessThan(1000),
        reason: 'cheat sheet of 10 pages took ${timer.elapsedMilliseconds} ms',
      );
    });
  });

  testWidgets('book -> "Разминка" -> words -> tap -> definition', (
    tester,
  ) async {
    final packs = _installPacks();
    final books = FakeBookRepository();
    await books.save(_book());
    final adapter = FakeBookFormatAdapter()
      ..register(
        '/x/b1.epub',
        const BookMetadata(title: 'Dune'),
        chapters: ['The ephemeral light was ubiquitous. A cat sat.'],
      );
    final dictionary = FakeLookupProvider(
      id: _pid,
      answers: const {
        'ephemeral': LookupResult(
          provider: _pid,
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

    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
    }

    await settle();
    // On a phone the menu is hidden while reading; a margin tap shows it.
    await tester.tapAt(const Offset(4, 300));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
    await settle();
    await tester.pump(const Duration(milliseconds: 300)); // the bar slides in
    await tester.tap(find.byTooltip('Разминка'));
    await settle();

    expect(find.text('Не удалось подготовить разминку.'), findsNothing);
    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.text('ubiquitous'), findsOneWidget);
    expect(find.text('cat'), findsNothing);

    await tester.tap(find.text('ephemeral'));
    await settle();
    await tester.pumpAndSettle();
    expect(find.text('1. lasting a very short time'), findsOneWidget);
  });
}
