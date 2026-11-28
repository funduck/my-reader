import 'package:material_ui/material_ui.dart';

/// A label: a read-only piece of information (level, frequency, "looked up
/// ×N", status).
///
/// The look of a label is fixed by the rule in `DECISIONS.md`: no border, no
/// tap response, never focusable, a light fill behind the content. A label is
/// the only way to draw such a fact; a button or a `ToggleButton` is for
/// something to press.
///
/// For a screen reader a label is text, not a button.
class InfoLabel extends StatelessWidget {
  /// Creates a label around [child].
  ///
  /// [child] is usually a [Text]; it gets the label text style. A screen
  /// reader reads [semanticsLabel] instead of the [child] when it is set (a
  /// short `≈B2` becomes "Level about B2"), and the [child] as it is when not.
  const new({required this.child, this.semanticsLabel, super.key});

  /// What the label shows.
  final Widget child;

  /// What a screen reader says instead of the [child], or `null` to read the
  /// [child].
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 8,
          vertical: 2,
        ),
        child: DefaultTextStyle.merge(
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          child: child,
        ),
      ),
    );
    final text = semanticsLabel;
    if (text == null) return label;
    return Semantics(label: text, excludeSemantics: true, child: label);
  }
}
