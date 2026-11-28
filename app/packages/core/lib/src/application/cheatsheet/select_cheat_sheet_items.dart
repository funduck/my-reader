import '../../domain/lookup/cefr_level.dart';
import '../../domain/lookup/cheat_sheet.dart';
import 'cheat_sheet_config.dart';

/// Picks the items to show from all candidates of a cheat sheet.
///
/// Keeps the items that [isDifficult] accepts: strictly harder than [above]
/// (an unknown level is never harder) or looked up before, never those whose
/// text is in [hidden]. Orders them from frequent
/// to rare ([CheatSheetItem.zipf] descending, items without it last; equal
/// ones keep the order of [items]) and takes the first [limit]; a null [limit]
/// takes all. With [minBars] above 1 only items with
/// `zipfBars(zipf) >= minBars` stay; those without a Zipf frequency are
/// dropped. Looked-up words skip the level and the threshold (T-121) and take
/// part in the same order and limit: no quota of their own.
List<CheatSheetItem> selectCheatSheetItems(
  List<CheatSheetItem> items, {
  required CefrLevel above,
  required int? limit,
  Set<String> hidden = const {},
  int minBars = 1,
}) {
  final picked =
      <(int, CheatSheetItem)>[
        for (var i = 0; i < items.length; i++)
          if (isDifficult(
            items[i],
            above: above,
            minBars: minBars,
            hidden: hidden,
          ))
            (i, items[i]),
      ]..sort((a, b) {
        final za = a.$2.zipf;
        final zb = b.$2.zipf;
        if (za != zb) {
          if (za == null) return 1;
          if (zb == null) return -1;
          return zb.compareTo(za);
        }
        return a.$1 - b.$1;
      });
  final all = [for (final (_, item) in picked) item];
  return limit == null || limit >= all.length ? all : all.sublist(0, limit);
}

/// Number of frequency bars (1..5) for a Zipf frequency; null without one.
int? zipfBars(double? zipf) {
  if (zipf == null) return null;
  if (zipf >= zipfBars5) return 5;
  if (zipf >= zipfBars4) return 4;
  if (zipf >= zipfBars3) return 3;
  if (zipf >= zipfBars2) return 2;
  return 1;
}

/// Whether [item] counts as difficult (T-121). Two ways in:
///
/// - the word was looked up (`kind == word` and `lookupCount > 0`): always,
///   whatever its level, frequency or proper-name flag;
/// - its level is strictly above [above], it is not a proper name and it has
///   at least [minBars] frequency bars (an item without a Zipf frequency
///   fails when [minBars] is above 1).
///
/// A text in [hidden] (the words marked known) is never difficult. The same
/// rule as the cheat sheet applies, without the limit.
bool isDifficult(
  CheatSheetItem item, {
  required CefrLevel above,
  int minBars = 1,
  Set<String> hidden = const {},
}) {
  if (hidden.contains(item.text)) return false;
  if (item.kind == CheatSheetItemKind.word && item.lookupCount > 0) {
    return true;
  }
  if (item.isProperName || !item.level.isHarderThan(above)) return false;
  return minBars <= 1 || (zipfBars(item.zipf) ?? 0) >= minBars;
}
