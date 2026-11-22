import 'package:core/domain_books.dart';
import 'package:core/ports.dart';

import 'change_feed.dart';

/// In-memory [BookRepository].
///
/// It does not know about progress, so [remove] does not delete it; the
/// storage adapter does that in one transaction.
class FakeBookRepository implements BookRepository {
  /// Creates an empty repository.
  new();

  final Map<BookId, Book> _books = {};
  final ChangeFeed _feed = ChangeFeed();

  List<Book> _snapshot() {
    // Stable sort over reversed insertion order: among equal dates the later
    // save comes first.
    final list = _books.values.toList().reversed.toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return List.unmodifiable(list);
  }

  @override
  Stream<List<Book>> watchAll() => _feed.watch(_snapshot);

  @override
  Future<Book?> get(BookId id) async => _books[id];

  @override
  Future<Book?> findByContentHash(String contentHash) async {
    for (final book in _books.values) {
      if (book.contentHash == contentHash) return book;
    }
    return null;
  }

  @override
  Future<void> save(Book book) async {
    _books[book.id] = book;
    _feed.notify();
  }

  @override
  Future<void> remove(BookId id) async {
    if (_books.remove(id) != null) _feed.notify();
  }
}
