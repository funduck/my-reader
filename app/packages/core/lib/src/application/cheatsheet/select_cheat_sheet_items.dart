import '../../domain/lookup/cefr_level.dart';
import '../../domain/lookup/cheat_sheet.dart';
import 'cheat_sheet_config.dart';

/// Picks the items to show from all candidates of a cheat sheet.
///
/// Keeps items strictly harder than [above] (an unknown level is never
/// harder), drops those whose text is in [hidden], orders them from frequent
/// to rare ([CheatSheetItem.zipf] descending, items without it last; equal
/// ones keep the order of [items]) and takes the first [limit]; a null [limit]
/// takes all. With [minBars] above 1 only items with
/// `zipfBars(zipf) >= minBars` stay; those without a Zipf frequency are
/// dropped.
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

/// Whether [item] counts as difficult: its level is strictly above [above],
/// its text is not in [hidden] and it has at least [minBars] frequency bars
/// (an item without a Zipf frequency fails when [minBars] is above 1).
///
/// The same rule as the cheat sheet applies, without the limit.
bool isDifficult(
  CheatSheetItem item, {
  required CefrLevel above,
  int minBars = 1,
  Set<String> hidden = const {},
}) {
  if (!item.level.isHarderThan(above) || hidden.contains(item.text)) {
    return false;
  }
  return minBars <= 1 || (zipfBars(item.zipf) ?? 0) >= minBars;
}
