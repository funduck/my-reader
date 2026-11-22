import 'package:logging/logging.dart';

import '../domain/books/locator.dart';
import '../domain/books/reading_progress.dart';
import '../ports/clock.dart';
import '../ports/repositories.dart';

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
  /// chapters of the book; the whole-book fraction is estimated as
  /// `(chapter index + progression) / chapterCount`, clamped to 0..1.
  Future<void> call(Locator at, {required int chapterCount}) {
    final raw = chapterCount <= 0
        ? 0.0
        : (at.chapter.index + at.progression) / chapterCount;
    final percent = raw.clamp(0.0, 1.0);
    _log.fine('Save ${at.book}: $percent');
    return progress.save(
      ReadingProgress(locator: at, percent: percent, updatedAt: clock.now()),
    );
  }
}
