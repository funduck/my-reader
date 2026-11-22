import 'dart:io';

import 'package:logging/logging.dart';

import '../domain/books/book.dart';
import '../domain/books/ids.dart';
import '../ports/book_format_adapter.dart';
import '../ports/clock.dart';
import '../ports/id_generator.dart';
import '../ports/repositories.dart';

/// Computes the content hash of the file at an absolute path.
typedef FileHasher = Future<String> Function(String path);

/// What [ImportBook] returns. Expected failures are values, not exceptions.
sealed class ImportOutcome {
  const new();
}

/// The file was copied and the book saved.
final class BookImported extends ImportOutcome {
  /// Creates the outcome.
  const new(this.book);

  /// The saved book.
  final Book book;
}

/// A book with the same content is already in the library; nothing changed.
final class BookAlreadyImported extends ImportOutcome {
  /// Creates the outcome.
  const new(this.book);

  /// The existing book.
  final Book book;
}

/// No adapter can open the file, or its metadata is broken.
final class BookUnsupported extends ImportOutcome {
  /// Creates the outcome.
  const new(this.path);

  /// Path of the rejected file.
  final String path;
}

/// Imports a book: picks a format adapter, reads metadata, copies the file
/// under its content hash into [directory] and saves the [Book].
///
/// Importing the same content twice returns the existing book.
class ImportBook {
  /// Creates the use case. [adapters] are tried in order.
  const new({
    required this.adapters,
    required this.books,
    required this.clock,
    required this.ids,
    required this.directory,
    required this.hash,
  });

  /// Format adapters in the order they are tried.
  final List<BookFormatAdapter> adapters;

  /// Library storage.
  final BookRepository books;

  /// Source of `Book.addedAt`.
  final Clock clock;

  /// Source of book ids.
  final IdGenerator ids;

  /// Absolute path of the directory where book files are copied.
  final String directory;

  /// Content hash of a file; also the name of the stored copy.
  final FileHasher hash;

  static final Logger _log = Logger('ImportBook');

  /// Imports the file at the absolute [path].
  ///
  /// Throws [FileSystemException] if the file cannot be read or copied.
  Future<ImportOutcome> call(String path) async {
    _log.info('Importing $path');
    final adapter = await _adapterFor(path);
    if (adapter == null) {
      _log.warning('No format adapter can open $path');
      return BookUnsupported(path);
    }

    final BookMetadata metadata;
    try {
      metadata = await adapter.readMetadata(path);
    } on FormatException catch (e, s) {
      _log.warning('Broken metadata in $path', e, s);
      return BookUnsupported(path);
    }

    final contentHash = await hash(path);
    final existing = await books.findByContentHash(contentHash);
    if (existing != null) {
      _log.info('Already imported as ${existing.id.value}');
      return BookAlreadyImported(existing);
    }

    final format = adapter.formats.first;
    await Directory(directory).create(recursive: true);
    final stored =
        '$directory${Platform.pathSeparator}$contentHash.${format.name}';
    await File(path).copy(stored);

    final book = Book(
      id: BookId(ids.newId()),
      metadata: metadata.title.trim().isEmpty
          ? metadata.copyWith(title: _fileTitle(path))
          : metadata,
      format: format,
      filePath: stored,
      contentHash: contentHash,
      addedAt: clock.now(),
    );
    try {
      await books.save(book);
    } on Object catch (e, s) {
      _log.severe('Cannot save book ${book.id.value}', e, s);
      await File(stored).delete();
      rethrow;
    }
    _log.info(
      'Imported ${book.id.value} "${book.metadata.title}" as ${format.name}',
    );
    return BookImported(book);
  }

  Future<BookFormatAdapter?> _adapterFor(String path) async {
    for (final adapter in adapters) {
      try {
        if (await adapter.canOpen(path)) return adapter;
      } on FormatException catch (e) {
        _log.fine('${adapter.runtimeType} cannot open $path: $e');
        continue;
      }
    }
    return null;
  }

  static String _fileTitle(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}
