import 'package:core/domain_books.dart';
import 'package:core/ports.dart';

import 'change_feed.dart';

/// In-memory [ProgressRepository].
class FakeProgressRepository implements ProgressRepository {
  /// Creates an empty repository.
  new();

  final Map<BookId, ReadingProgress> _items = {};
  final Map<BookId, ChangeFeed> _feeds = {};

  ChangeFeed _feed(BookId book) => _feeds.putIfAbsent(book, ChangeFeed.new);

  @override
  Future<ReadingProgress?> get(BookId book) async => _items[book];

  @override
  Stream<ReadingProgress?> watch(BookId book) =>
      _feed(book).watch(() => _items[book]);

  @override
  Future<void> save(ReadingProgress progress) async {
    final book = progress.locator.book;
    _items[book] = progress;
    _feed(book).notify();
  }
}
