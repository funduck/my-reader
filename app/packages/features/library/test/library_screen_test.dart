import 'dart:io';

import 'package:core/domain_books.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:features_library/features_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late Directory tmp;
  late FakeBookRepository books;
  late FakeProgressRepository progress;
  late FakeBookFormatAdapter adapter;
  late String? picked;
  late List<BookId> opened;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('library_screen_test');
    books = FakeBookRepository();
    progress = FakeProgressRepository();
    adapter = FakeBookFormatAdapter();
    picked = null;
    opened = [];
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> pumpLibrary(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookRepositoryProvider.overrideWithValue(books),
          progressRepositoryProvider.overrideWithValue(progress),
          bookFormatsProvider.overrideWithValue([adapter]),
          clockProvider.overrideWithValue(FakeClock()),
          idGeneratorProvider.overrideWithValue(SeqIdGenerator(prefix: 'b')),
          booksDirectoryProvider.overrideWithValue('${tmp.path}/books'),
          bookPickerProvider.overrideWithValue(() async => picked),
        ],
        child: MaterialApp(home: LibraryScreen(onOpenBook: opened.add)),
      ),
    );
    await tester.pump();
  }

  // Real file IO completes outside the fake-async zone, so alternate between
  // waiting for the event loop and pumping microtasks.
  Future<void> tapImport(WidgetTester tester) async {
    await tester.tap(find.text('Import book'));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
  }

  Book book(String id, String title, {String? author}) => Book(
    id: BookId(id),
    metadata: BookMetadata(title: title, author: author),
    format: BookFormat.epub,
    filePath: '/x/$id.epub',
    contentHash: 'h$id',
    addedAt: DateTime.utc(2024),
  );

  testWidgets('shows a hint when the library is empty', (tester) async {
    await pumpLibrary(tester);
    expect(find.text('No books yet. Import an EPUB.'), findsOneWidget);
  });

  testWidgets('lists books with author and percent, tap opens one', (
    tester,
  ) async {
    await books.save(book('a', 'Dune', author: 'Herbert'));
    await books.save(book('b', 'Emma'));
    await progress.save(
      ReadingProgress(
        locator: const Locator(
          book: BookId('a'),
          chapter: ChapterRef(index: 0, href: 'c.xhtml'),
          progression: 0.42,
        ),
        percent: 0.42,
        updatedAt: DateTime.utc(2024),
      ),
    );
    await pumpLibrary(tester);
    await tester.pump();

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Herbert'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('Emma'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);

    await tester.tap(find.text('Dune'));
    expect(opened, [const BookId('a')]);
  });

  testWidgets('import adds the picked book to the list', (tester) async {
    final file = File('${tmp.path}/dune.epub')..writeAsStringSync('epub');
    adapter.register(
      file.path,
      const BookMetadata(title: 'Dune', author: 'Herbert'),
    );
    picked = file.path;
    await pumpLibrary(tester);

    await tapImport(tester);
    await tester.pump();
    await tester.pump();

    expect(find.text('Added: Dune'), findsOneWidget);
    expect(find.text('Herbert'), findsOneWidget);
    expect(Directory('${tmp.path}/books').listSync(), hasLength(1));
  });

  testWidgets('an unsupported file shows a message', (tester) async {
    final file = File('${tmp.path}/notes.txt')..writeAsStringSync('text');
    picked = file.path;
    await pumpLibrary(tester);

    await tapImport(tester);
    await tester.pump();
    await tester.pump();

    expect(find.text('This file is not a supported book.'), findsOneWidget);
    expect(find.text('No books yet. Import an EPUB.'), findsOneWidget);
  });

  testWidgets('a cancelled dialog changes nothing', (tester) async {
    await pumpLibrary(tester);
    await tapImport(tester);
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('No books yet. Import an EPUB.'), findsOneWidget);
  });
}
