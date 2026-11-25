import '../domain/books/ids.dart';
import '../domain/lookup/cheat_sheet_snapshot.dart';

/// The last cheat sheet shown for each book.
///
/// Holds one snapshot per book: a new one replaces the old.
abstract interface class CheatSheetLog {
  /// Stores [snapshot] as the last cheat sheet of `snapshot.book`, replacing
  /// the previous one.
  Future<void> save(CheatSheetSnapshot snapshot);

  /// Emits the last snapshot of [book] and again on every change; null while
  /// no cheat sheet of the book was shown.
  Stream<CheatSheetSnapshot?> watch(BookId book);
}
