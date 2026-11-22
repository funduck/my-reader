import '../domain/books/locator.dart';
import '../domain/lookup/cefr_level.dart';
import '../domain/lookup/cheat_sheet.dart';
import 'cancel_token.dart';

/// Builds the pre-reading cheat sheet for a piece of text (S-1..S-5).
abstract interface class CheatSheetGenerator {
  /// Finds words in [text] harder than [userLevel] and returns them as a sheet
  /// covering [from]..[to]; words in [knownTerms] (normalized) are skipped.
  Future<CheatSheet> generate({
    required String text,
    required Locator from,
    required Locator to,
    required CefrLevel userLevel,
    Set<String> knownTerms = const {},
    CancelToken? cancel,
  });
}
