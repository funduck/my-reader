import '../domain/books/locator.dart';
import '../domain/lookup/cheat_sheet.dart';
import 'cancel_token.dart';

/// Builds the pre-reading cheat sheet for a piece of text (S-1..S-5).
abstract interface class CheatSheetGenerator {
  /// Finds all candidate words of [text] (any known level, proper names and
  /// [knownTerms] left out) and returns them as a sheet covering [from]..[to].
  /// Choosing by level and count is up to the caller (`selectCheatSheetItems`).
  Future<CheatSheet> generate({
    required String text,
    required Locator from,
    required Locator to,
    Set<String> knownTerms = const {},
    CancelToken? cancel,
  });
}
