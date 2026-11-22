import 'dart:io';

import 'package:logging/logging.dart';

import '../domain/books/book.dart';
import '../domain/books/ids.dart';
import '../domain/books/locator.dart';
import '../ports/book_format_adapter.dart';
import '../ports/repositories.dart';

final Logger _log = Logger('OpenBook');

/// What [OpenBook] returns. Expected failures are values, not exceptions.
sealed class OpenBookOutcome {
  const new();
}

/// The book is open.
final class BookOpened extends OpenBookOutcome {
  /// Creates the outcome; the caller must close [opened].
  const new({required this.book, required this.opened, this.resumeAt});

  /// The library entry.
  final Book book;

  /// The open book; owned by the caller.
  final OpenedBook opened;

  /// The saved reading position, or null if the book was never read.
  final Locator? resumeAt;
}

/// There is no book with the requested id.
final class BookNotFound extends OpenBookOutcome {
  /// Creates the outcome.
  const new(this.id);

  /// The requested id.
  final BookId id;
}

/// The book is in the library but its file cannot be opened.
final class BookFileUnreadable extends OpenBookOutcome {
  /// Creates the outcome.
  const new(this.book, this.reason);

  /// The library entry.
  final Book book;

  /// What went wrong, for the user and the log.
  final String reason;
}

/// Opens a library book for reading and finds where the reader stopped (R-2).
class OpenBook {
  /// Creates the use case; [adapters] are tried in order.
  const new({
    required this.adapters,
    required this.books,
    required this.progress,
  });

  /// Format adapters, tried in order.
  final List<BookFormatAdapter> adapters;

  /// Library storage.
  final BookRepository books;

  /// Saved positions.
  final ProgressRepository progress;

  /// Opens the book [id] and loads its saved position.
  ///
  /// Never throws for a missing book or an unreadable file.
  Future<OpenBookOutcome> call(BookId id) async {
    final book = await books.get(id);
    if (book == null) {
      _log.warning('Book $id not found');
      return BookNotFound(id);
    }
    final adapter = adapters
        .where((a) => a.formats.contains(book.format))
        .firstOrNull;
    if (adapter == null) {
      _log.warning('No adapter for ${book.format}');
      return BookFileUnreadable(book, 'No reader for ${book.format.name}.');
    }
    final OpenedBook opened;
    try {
      opened = await adapter.open(book.filePath);
    } on FormatException catch (e, s) {
      _log.warning('Book $id is not readable', e, s);
      return BookFileUnreadable(book, e.message);
    } on FileSystemException catch (e, s) {
      _log.warning('Book file of $id is missing', e, s);
      return BookFileUnreadable(book, e.message);
    }
    final saved = await progress.get(id);
    _log.info('Opened $id, resume: ${saved != null}');
    return BookOpened(book: book, opened: opened, resumeAt: saved?.locator);
  }
}
