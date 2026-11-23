import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';

import 'change_feed.dart';

/// In-memory [PhraseJournal].
///
/// Newest first by `at`; among equal times the later record comes first.
class FakePhraseJournal implements PhraseJournal {
  /// Creates an empty journal.
  new();

  final List<PhraseLookup> _items = [];
  final ChangeFeed _feed = ChangeFeed();

  List<PhraseLookup> _snapshot({BookId? book}) {
    final list = [
      for (final p in _items.reversed)
        if (book == null || p.locator.book == book) p,
    ]..sort((a, b) => b.at.compareTo(a.at));
    return List.unmodifiable(list);
  }

  @override
  Future<void> record(PhraseLookup phrase) async {
    if (_items.any((p) => p.id == phrase.id)) return;
    _items.add(phrase);
    _feed.notify();
  }

  @override
  Stream<List<PhraseLookup>> watchAll() => _feed.watch(_snapshot);

  @override
  Future<List<PhraseLookup>> byBook(BookId book) async => _snapshot(book: book);

  @override
  Future<void> delete(PhraseLookupId id) async {
    final before = _items.length;
    _items.removeWhere((p) => p.id == id);
    if (_items.length != before) _feed.notify();
  }
}
