import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:material_ui/material_ui.dart';

/// CEFR level of a word as a chip: `C1`, or `≈B2` when the level was
/// estimated from frequency rather than taken from a CEFR list.
///
/// Draws nothing when the level is [CefrLevel.unknown].
class LevelBadge extends StatelessWidget {
  /// Creates the badge for [level].
  const new({required this.level, super.key});

  /// What the level dictionary said about the word.
  final WordLevel level;

  @override
  Widget build(BuildContext context) {
    if (!level.level.isKnown) return const SizedBox.shrink();
    final name = level.level.name.toUpperCase();
    final text = level.estimated ? '≈$name' : name;
    return Semantics(
      label: level.estimated ? 'Level about $name' : 'Level $name',
      excludeSemantics: true,
      child: Chip(label: Text(text)),
    );
  }
}
