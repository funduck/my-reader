import '../../domain/books/chapter_ref.dart';
import '../../domain/books/ids.dart';
import '../../domain/books/locator.dart';
import '../../domain/lookup/cefr_level.dart';
import '../../domain/lookup/cheat_sheet.dart';
import '../../domain/profile/cheat_sheet_scope.dart';
import '../../ports/book_format_adapter.dart';
import '../../ports/cancel_token.dart';
import '../../ports/cheat_sheet_generator.dart';
import 'select_cheat_sheet_items.dart';
import 'text_range.dart';

/// Finds the words of one chapter that are hard for the reader (B-019, p. 1).
///
/// The text of the chapter is the one the cheat sheet would analyse
/// ([selectCheatSheetRange] with [CheatSheetChapter]); the same
/// [CheatSheetGenerator] gives the candidates. Choosing is the rule of
/// [isDifficult]: a level strictly above the reader's with `zipfBars >=
/// minBars`, or a word looked up before (T-121), unless marked known. The
/// generator is asked about no known terms and drops nothing (unknown levels
/// and proper names come flagged), so a word that is looked up later is
/// already among the candidates.
///
/// The slow part is [candidates]; [pick] is cheap, so a screen that keeps the
/// candidates of the chapter calls only [pick] when the level, the threshold
/// or the marks change.
final class ChapterDifficultWords {
  /// Creates the use case over [generator].
  const new({required this.generator});

  /// Finds the candidate words of a text.
  final CheatSheetGenerator generator;

  /// All candidates of [chapter]: every lemma, as the generator returns them
  /// (unknown levels and proper names included, flagged).
  ///
  /// Returns an empty list when the chapter is not in `book.spine` or has no
  /// text. Throws [CancelledException] if [cancel] fires.
  Future<List<CheatSheetItem>> candidates(
    OpenedBook book,
    BookId bookId,
    ChapterRef chapter, {
    CancelToken? cancel,
  }) async {
    final range = await selectCheatSheetRange(
      book,
      from: Locator(book: bookId, chapter: chapter, progression: 0),
      scope: const CheatSheetChapter(),
    );
    cancel?.throwIfCancelled();
    if (range == null) return const [];
    final sheet = await generator.generate(
      text: range.text,
      from: range.start,
      to: range.end,
      cancel: cancel,
    );
    cancel?.throwIfCancelled();
    return sheet.items;
  }

  /// The lemmas among [candidates] that are difficult for [level]: words
  /// strictly above it, with at least [minBars] frequency bars, and the words
  /// in [lookedUp] (lemma to the number of lookups, only those above 0 count),
  /// whatever their level, frequency or proper-name flag. A lemma in [known]
  /// is never taken. Only single words are taken. Cheap: no text analysis.
  Set<String> pick(
    List<CheatSheetItem> candidates, {
    required CefrLevel level,
    int minBars = 1,
    Set<String> known = const {},
    Map<String, int> lookedUp = const {},
  }) => {
    for (final item in candidates)
      if (item.kind == CheatSheetItemKind.word &&
          isDifficult(
            lookedUp[item.text] == null
                ? item
                : item.copyWith(lookupCount: lookedUp[item.text]),
            above: level,
            minBars: minBars,
            hidden: known,
          ))
        item.text,
  };

  /// The difficult lemmas of [chapter]: [candidates] and then [pick].
  Future<Set<String>> call(
    OpenedBook book,
    BookId bookId,
    ChapterRef chapter, {
    required CefrLevel level,
    int minBars = 1,
    Set<String> known = const {},
    Map<String, int> lookedUp = const {},
    CancelToken? cancel,
  }) async => pick(
    await candidates(book, bookId, chapter, cancel: cancel),
    level: level,
    minBars: minBars,
    known: known,
    lookedUp: lookedUp,
  );
}
