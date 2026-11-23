import '../domain/books/ids.dart';
import '../domain/lookup/ids.dart';
import '../domain/lookup/phrase_lookup.dart';

/// Journal of translated phrases, separate from `LookupJournal` and terms.
abstract interface class PhraseJournal {
  /// Stores the entry; recording an id that is already stored does nothing.
  Future<void> record(PhraseLookup phrase);

  /// Emits all entries, newest first, and again on every change.
  Stream<List<PhraseLookup>> watchAll();

  /// Returns the entries made in [book], newest first.
  Future<List<PhraseLookup>> byBook(BookId book);

  /// Removes the entry; an unknown [id] does nothing.
  Future<void> delete(PhraseLookupId id);
}
