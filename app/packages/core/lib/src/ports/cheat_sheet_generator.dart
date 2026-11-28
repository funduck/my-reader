import '../domain/books/locator.dart';
import '../domain/lookup/cheat_sheet.dart';
import 'cancel_token.dart';

/// Builds the pre-reading cheat sheet for a piece of text (S-1..S-5).
abstract interface class CheatSheetGenerator {
  /// Finds all candidate words of [text] (any level, [knownTerms] left out)
  /// and returns them as a sheet covering [from]..[to].
  ///
  /// Words of an unknown level and proper names are returned too: the latter
  /// carry `CheatSheetItem.isProperName`. They are difficult only once looked
  /// up (T-121), and the caller learns that later, so nothing is dropped
  /// here. Choosing by level and count is up to the caller
  /// (`selectCheatSheetItems`).
  Future<CheatSheet> generate({
    required String text,
    required Locator from,
    required Locator to,
    Set<String> knownTerms = const {},
    CancelToken? cancel,
  });
}
