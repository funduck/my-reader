import '../../domain/lookup/cefr_level.dart';
import '../../domain/lookup/cheat_sheet.dart';
import 'cheat_sheet_config.dart';

/// Picks the items to show from all candidates of a cheat sheet.
///
/// Keeps items strictly harder than [above] (an unknown level is never
/// harder), drops those whose text is in [hidden], orders them from frequent
/// to rare ([CheatSheetItem.zipf] descending, items without it last; equal
/// ones keep the order of [items]) and takes the first [limit]; a null [limit]
/// takes all.
List<CheatSheetItem> selectCheatSheetItems(
  List<CheatSheetItem> items, {
  required CefrLevel above,
  required int? limit,
  Set<String> hidden = const {},
}) {
  final picked =
      <(int, CheatSheetItem)>[
        for (var i = 0; i < items.length; i++)
          if (items[i].level.isHarderThan(above) &&
              !hidden.contains(items[i].text))
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
