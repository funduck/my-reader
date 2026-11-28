import '../../domain/books/locator.dart';
import '../../domain/lookup/cheat_sheet.dart';
import '../../domain/lookup/term_status.dart';
import '../../ports/book_format_adapter.dart';
import '../../ports/cancel_token.dart';
import '../../ports/cheat_sheet_generator.dart';
import '../../ports/repositories.dart';
import 'cheat_sheet_config.dart';
import 'text_range.dart';

/// Builds the cheat sheet for the piece of the book after a position (S-1).
///
/// Reads the profile (level and piece size), picks the piece with
/// [selectCheatSheetRange], hands the lemmas marked known to the
/// [CheatSheetGenerator] (they are left out) and puts the number of lookups
/// on the words the user translated (`CheatSheetItem.lookupCount`, T-121):
/// those stay in the sheet, whatever their level. Definitions are not fetched
/// here: the screen asks the lookup providers when it shows an item.
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

  /// Source of the lemmas looked up and marked known before.
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
    final history = await terms.watchAll().first;
    cancel?.throwIfCancelled();
    final known = <String>{};
    final lookups = <String, int>{};
    for (final t in history) {
      if (t.language != cheatSheetLanguage) continue;
      if (t.status == TermStatus.known) {
        known.add(t.normalized);
      } else if (t.lookupCount > 0) {
        lookups[t.normalized] = t.lookupCount;
      }
    }
    final sheet = await generator.generate(
      text: range.text,
      from: range.start,
      to: range.end,
      knownTerms: known,
      cancel: cancel,
    );
    if (lookups.isEmpty) return sheet;
    return CheatSheet(
      from: sheet.from,
      to: sheet.to,
      items: [
        for (final item in sheet.items)
          if (item.kind == CheatSheetItemKind.word &&
              lookups[item.text] != null)
            item.copyWith(lookupCount: lookups[item.text])
          else
            item,
      ],
    );
  }
}
