import 'package:logging/logging.dart';

import '../domain/books/locator.dart';
import '../domain/books/reading_progress.dart';
import '../ports/clock.dart';
import '../ports/repositories.dart';
import 'book_fraction.dart';

final Logger _log = Logger('SaveProgress');

/// Saves the reading position of a book (R-2).
class SaveProgress {
  /// Creates the use case.
  const new({required this.progress, required this.clock});

  /// Where positions are stored.
  final ProgressRepository progress;

  /// Time of the save.
  final Clock clock;

  /// Saves [at] as the position of its book. [chapterCount] is the number of
  /// chapters of the book. The whole-book fraction is computed by
  /// [bookFraction]: by the text lengths in [chapterLengths] when they are
  /// known, else as `(chapter index + progression) / chapterCount`.
  Future<void> call(
    Locator at, {
    required int chapterCount,
    List<int>? chapterLengths,
  }) {
    final percent = bookFraction(
      at,
      chapterCount: chapterCount,
      chapterLengths: chapterLengths,
    );
    _log.fine('Save ${at.book}: $percent');
    return progress.save(
      ReadingProgress(locator: at, percent: percent, updatedAt: clock.now()),
    );
  }
}
