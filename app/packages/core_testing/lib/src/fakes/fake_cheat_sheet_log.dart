import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';

import 'change_feed.dart';

/// In-memory [CheatSheetLog].
class FakeCheatSheetLog implements CheatSheetLog {
  /// Creates an empty log.
  new();

  final Map<BookId, CheatSheetSnapshot> _items = {};
  final Map<BookId, ChangeFeed> _feeds = {};

  /// Every snapshot passed to [save], oldest first; for tests.
  final List<CheatSheetSnapshot> saved = [];

  ChangeFeed _feed(BookId book) => _feeds.putIfAbsent(book, ChangeFeed.new);

  @override
  Future<void> save(CheatSheetSnapshot snapshot) async {
    saved.add(snapshot);
    _items[snapshot.book] = snapshot;
    _feed(snapshot.book).notify();
  }

  @override
  Stream<CheatSheetSnapshot?> watch(BookId book) =>
      _feed(book).watch(() => _items[book]);
}
