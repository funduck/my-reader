import 'dart:async';
import 'dart:io';

import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:test/test.dart';

class _Adapter implements BookFormatAdapter {
  new(this.formats, this.accepted, {this.metadata, this.canOpenThrows = false});

  @override
  final Set<BookFormat> formats;
  final Set<String> accepted;
  final BookMetadata? metadata;
  final bool canOpenThrows;

  @override
  Future<bool> canOpen(String path) async {
    if (canOpenThrows) throw const FormatException('broken');
    return accepted.contains(path);
  }

  @override
  Future<BookMetadata> readMetadata(String path) async =>
      metadata ?? (throw const FormatException('no metadata'));

  @override
  Future<OpenedBook> open(String path) => throw UnimplementedError();
}

class _Books implements BookRepository {
  final Map<BookId, Book> items = {};
  bool failSave = false;

  @override
  Stream<List<Book>> watchAll() => const Stream.empty();

  @override
  Future<Book?> get(BookId id) async => items[id];

  @override
  Future<Book?> findByContentHash(String contentHash) async =>
      items.values.where((b) => b.contentHash == contentHash).firstOrNull;

  @override
  Future<void> save(Book book) async {
    if (failSave) throw StateError('disk full');
    items[book.id] = book;
  }

  @override
  Future<void> remove(BookId id) async => items.remove(id);
}

class _Clock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 1, 2);
}

class _Ids implements IdGenerator {
  int _n = 0;

  @override
  String newId() => 'book${++_n}';
}

void main() {
  late Directory tmp;
  late String source;
  late String storage;
  late _Books books;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('import_book_test');
    source = '${tmp.path}/Some Book.epub';
    File(source).writeAsStringSync('content-a');
    storage = '${tmp.path}/library/books';
    books = _Books();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<String> hash(String path) async =>
      'h-${File(path).readAsStringSync()}';

  ImportBook importer(List<BookFormatAdapter> adapters) => ImportBook(
    adapters: adapters,
    books: books,
    clock: _Clock(),
    ids: _Ids(),
    directory: storage,
    hash: hash,
  );

  const epubMeta = BookMetadata(
    title: 'Title',
    author: 'Author',
    language: 'en',
  );

  test('copies the file under its hash and saves the book', () async {
    final outcome = await importer([
      _Adapter({BookFormat.epub}, {source}, metadata: epubMeta),
    ])(source);

    final book = (outcome as BookImported).book;
    expect(book.id, const BookId('book1'));
    expect(book.metadata, epubMeta);
    expect(book.format, BookFormat.epub);
    expect(book.contentHash, 'h-content-a');
    expect(book.addedAt, DateTime.utc(2026, 1, 2));
    expect(book.filePath, '$storage/h-content-a.epub');
    expect(File(book.filePath).readAsStringSync(), 'content-a');
    expect(File(source).existsSync(), isTrue);
    expect(books.items.values, [book]);
  });

  test('picks the first adapter that can open the file', () async {
    final outcome = await importer([
      _Adapter({BookFormat.fb2}, {}, canOpenThrows: true),
      _Adapter({BookFormat.txt}, {}),
      _Adapter({BookFormat.epub}, {source}, metadata: epubMeta),
    ])(source);
    expect((outcome as BookImported).book.format, BookFormat.epub);
  });

  test('a file no adapter opens is unsupported', () async {
    final outcome = await importer([
      _Adapter({BookFormat.epub}, {}),
    ])(source);
    expect(outcome, isA<BookUnsupported>());
    expect((outcome as BookUnsupported).path, source);
    expect(books.items, isEmpty);
    expect(Directory(storage).existsSync(), isFalse);
  });

  test('broken metadata is unsupported', () async {
    final outcome = await importer([
      _Adapter({BookFormat.epub}, {source}),
    ])(source);
    expect(outcome, isA<BookUnsupported>());
    expect(books.items, isEmpty);
  });

  test('the same content is imported once', () async {
    final useCase = importer([
      _Adapter({BookFormat.epub}, {source}, metadata: epubMeta),
    ]);
    final first = (await useCase(source) as BookImported).book;
    final second = await useCase(source);
    expect(second, isA<BookAlreadyImported>());
    expect((second as BookAlreadyImported).book, first);
    expect(books.items, hasLength(1));
  });

  test('an empty title falls back to the file name', () async {
    final outcome = await importer([
      _Adapter(
        {BookFormat.epub},
        {source},
        metadata: const BookMetadata(title: '  ', author: 'A'),
      ),
    ])(source);
    final metadata = (outcome as BookImported).book.metadata;
    expect(metadata.title, 'Some Book');
    expect(metadata.author, 'A');
  });

  test('a failed save removes the copied file', () async {
    books.failSave = true;
    final useCase = importer([
      _Adapter({BookFormat.epub}, {source}, metadata: epubMeta),
    ]);
    await expectLater(useCase(source), throwsStateError);
    expect(File('$storage/h-content-a.epub').existsSync(), isFalse);
  });
}
