import 'dart:io';
import 'dart:typed_data';

import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:test/test.dart';

class _Opened implements OpenedBook {
  @override
  List<TocEntry> get toc => const [];
  @override
  List<ChapterRef> get spine => const [];
  @override
  Future<ContentDocument> chapter(ChapterRef ref) => throw UnimplementedError();
  @override
  Future<Uint8List> resource(String href) => throw UnimplementedError();
  @override
  Future<void> close() async {}
}

class _Adapter implements BookFormatAdapter {
  new(this.formats, {this.error});

  @override
  final Set<BookFormat> formats;
  final Exception? error;
  final List<String> opened = [];

  @override
  Future<bool> canOpen(String path) async => true;
  @override
  Future<BookMetadata> readMetadata(String path) => throw UnimplementedError();
  @override
  Future<OpenedBook> open(String path) async {
    opened.add(path);
    if (error != null) throw error!;
    return _Opened();
  }
}

class _Books implements BookRepository {
  new(this.items);
  final Map<BookId, Book> items;
  @override
  Stream<List<Book>> watchAll() => const Stream.empty();
  @override
  Future<Book?> get(BookId id) async => items[id];
  @override
  Future<Book?> findByContentHash(String contentHash) async => null;
  @override
  Future<void> save(Book book) async => items[book.id] = book;
  @override
  Future<void> remove(BookId id) async => items.remove(id);
}

class _Progress implements ProgressRepository {
  final Map<BookId, ReadingProgress> items = {};
  @override
  Future<ReadingProgress?> get(BookId book) async => items[book];
  @override
  Stream<ReadingProgress?> watch(BookId book) => const Stream.empty();
  @override
  Future<void> save(ReadingProgress progress) async =>
      items[progress.locator.book] = progress;
}

void main() {
  const id = BookId('b1');
  final book = Book(
    id: id,
    metadata: const BookMetadata(title: 'T'),
    format: BookFormat.epub,
    filePath: '/x/b1.epub',
    contentHash: 'h',
    addedAt: DateTime.utc(2024),
  );
  const locator = Locator(
    book: id,
    chapter: ChapterRef(href: 'c.xhtml', index: 2),
    progression: 0.5,
  );
  late _Progress progress;

  OpenBook make(List<BookFormatAdapter> adapters, [Map<BookId, Book>? items]) =>
      OpenBook(
        adapters: adapters,
        books: _Books(items ?? {id: book}),
        progress: progress,
      );

  setUp(() => progress = _Progress());

  test('opens the book without a saved position', () async {
    final adapter = _Adapter({BookFormat.epub});
    final outcome = await make([adapter])(id);
    expect(outcome, isA<BookOpened>());
    final opened = outcome as BookOpened;
    expect(opened.book, book);
    expect(opened.resumeAt, isNull);
    expect(adapter.opened, ['/x/b1.epub']);
  });

  test('returns the saved position', () async {
    await progress.save(
      ReadingProgress(
        locator: locator,
        percent: 0.3,
        updatedAt: DateTime.utc(2024),
      ),
    );
    final outcome = await make([
      _Adapter({BookFormat.epub}),
    ])(id);
    expect((outcome as BookOpened).resumeAt, locator);
  });

  test('picks the adapter by format', () async {
    final fb2 = _Adapter({BookFormat.fb2});
    final epub = _Adapter({BookFormat.epub});
    await make([fb2, epub])(id);
    expect(fb2.opened, isEmpty);
    expect(epub.opened, hasLength(1));
  });

  test('unknown book', () async {
    final outcome = await make([
      _Adapter({BookFormat.epub}),
    ], {})(id);
    expect(outcome, isA<BookNotFound>());
  });

  test('no adapter for the format', () async {
    final outcome = await make([
      _Adapter({BookFormat.fb2}),
    ])(id);
    expect(outcome, isA<BookFileUnreadable>());
  });

  test('broken or missing file is a value, not an exception', () async {
    final broken = await make([
      _Adapter({BookFormat.epub}, error: const FormatException('bad zip')),
    ])(id);
    expect((broken as BookFileUnreadable).reason, 'bad zip');
    final missing = await make([
      _Adapter({BookFormat.epub}, error: const FileSystemException('gone')),
    ])(id);
    expect(missing, isA<BookFileUnreadable>());
  });
}
