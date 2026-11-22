import 'package:core/domain_books.dart';
import 'package:core/ports.dart';

import 'fake_opened_book.dart';

/// A [BookFormatAdapter] over books registered by path.
///
/// An unregistered path is "not a book": [canOpen] is false, other methods
/// throw [FormatException].
class FakeBookFormatAdapter implements BookFormatAdapter {
  /// Creates an adapter without books, serving [formats] (default epub).
  new({this.formats = const {BookFormat.epub}});

  @override
  final Set<BookFormat> formats;

  final Map<String, (BookMetadata, List<String>)> _books = {};

  /// Makes [path] open as a book with [metadata] and [chapters] (texts).
  void register(
    String path,
    BookMetadata metadata, {
    List<String> chapters = const ['Text.'],
  }) => _books[path] = (metadata, chapters);

  (BookMetadata, List<String>) _entry(String path) =>
      _books[path] ?? (throw FormatException('Not a book: $path'));

  @override
  Future<bool> canOpen(String path) async => _books.containsKey(path);

  @override
  Future<BookMetadata> readMetadata(String path) async => _entry(path).$1;

  @override
  Future<OpenedBook> open(String path) async =>
      FakeOpenedBook(chapters: _entry(path).$2);
}
