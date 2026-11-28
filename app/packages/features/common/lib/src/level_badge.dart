import 'package:core/ports.dart';
import 'package:material_ui/material_ui.dart';

import 'info_label.dart';

/// CEFR level of a word as a label: `C1`, or `≈B2` when the level was
/// estimated from frequency rather than taken from a CEFR list.
///
/// Draws nothing when the level is unknown. Every screen that shows the level
/// of a word uses it, so the level looks the same everywhere.
class LevelBadge extends StatelessWidget {
  /// Creates the label for [level].
  const new({required this.level, super.key});

  /// What the level dictionary said about the word.
  final WordLevel level;

  @override
  Widget build(BuildContext context) {
    if (!level.level.isKnown) return const SizedBox.shrink();
    final name = level.level.name.toUpperCase();
    final text = level.estimated ? '≈$name' : name;
    return InfoLabel(
      semanticsLabel: level.estimated ? 'Level about $name' : 'Level $name',
      child: Text(text),
    );
  }
}
