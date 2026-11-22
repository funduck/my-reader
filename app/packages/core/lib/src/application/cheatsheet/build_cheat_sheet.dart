import '../../domain/books/locator.dart';
import '../../domain/lookup/cheat_sheet.dart';
import '../../ports/book_format_adapter.dart';
import '../../ports/cancel_token.dart';
import '../../ports/cheat_sheet_generator.dart';
import '../../ports/repositories.dart';
import 'cheat_sheet_config.dart';
import 'text_range.dart';

/// Builds the cheat sheet for the piece of the book after a position (S-1).
///
/// Reads the profile (level and piece size), picks the piece with
/// [selectCheatSheetRange], collects the lemmas the user already looked up
/// (every term of the history, whatever its status) and hands all that to the
/// [CheatSheetGenerator]. Definitions are not fetched here: the screen asks
/// the lookup providers when it shows an item.
final class BuildCheatSheet {
  /// Creates the use case.
  const new({
    required this.generator,
    required this.profiles,
    required this.terms,
  });

  /// Finds the words of the piece.
  final CheatSheetGenerator generator;

  /// Source of the level and the piece size.
  final ProfileRepository profiles;

  /// Source of the lemmas looked up before.
  final TermRepository terms;

  /// Builds the sheet for [book] from [from].
  ///
  /// Returns null when there is nothing to analyse (see
  /// [selectCheatSheetRange]). Throws [CancelledException] if [cancel] fires.
  Future<CheatSheet?> call(
    OpenedBook book, {
    required Locator from,
    CancelToken? cancel,
  }) async {
    final profile = await profiles.get();
    cancel?.throwIfCancelled();
    final range = await selectCheatSheetRange(
      book,
      from: from,
      scope: profile.scope,
    );
    if (range == null) return null;
    cancel?.throwIfCancelled();
    final known = await terms.watchAll().first;
    cancel?.throwIfCancelled();
    return await generator.generate(
      text: range.text,
      from: range.start,
      to: range.end,
      userLevel: profile.level,
      knownTerms: {
        for (final t in known)
          if (t.language == cheatSheetLanguage) t.normalized,
      },
      cancel: cancel,
    );
  }
}
