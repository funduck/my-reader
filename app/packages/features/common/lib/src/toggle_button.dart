import 'package:material_ui/material_ui.dart';

/// A button that switches something on and off, or picks one of several
/// choices ("Знаю", a book filter).
///
/// The rule in `DECISIONS.md`: a button is visibly pressable. Off, it is an
/// outlined button; on, a filled one with a check mark before the text, so
/// the state shows without colour. A screen reader gets one button with a
/// toggled state.
class ToggleButton extends StatelessWidget {
  /// Creates a toggle named [label].
  ///
  /// [onChanged] gets the state the press asks for (the opposite of
  /// [selected]); `null` disables the button.
  const new({
    required this.label,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  /// The text of the button.
  final String label;

  /// Whether the toggle is on.
  final bool selected;

  /// Called with the new state when the button is pressed.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    final onPressed = switch (onChanged) {
      null => null,
      final change => () => change(!selected),
    };
    const style = compactButtonStyle;
    final button = selected
        ? FilledButton.tonalIcon(
            onPressed: onPressed,
            style: style,
            icon: const Icon(Icons.check, size: 18),
            label: Text(label),
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: style,
            child: Text(label),
          );
    return Semantics(
      container: true,
      button: true,
      toggled: selected,
      enabled: onPressed != null,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: button,
    );
  }
}

/// The one shape of the small buttons next to a word (the lookup sheet, the
/// cheat sheet, history): the same height with or without an icon, so a row
/// of them lines up. The tap target stays 48 px (`MaterialTapTargetSize`).
///
/// The density is fixed: a compact density (the desktop default) would take
/// 8 px off [compactButtonHeight].
const ButtonStyle compactButtonStyle = ButtonStyle(
  visualDensity: VisualDensity.standard,
  minimumSize: WidgetStatePropertyAll(Size(44, compactButtonHeight)),
  maximumSize: WidgetStatePropertyAll(
    Size(double.infinity, compactButtonHeight),
  ),
  padding: WidgetStatePropertyAll(
    EdgeInsetsDirectional.symmetric(horizontal: 12),
  ),
  iconSize: WidgetStatePropertyAll(18),
);

/// Height of [compactButtonStyle] buttons, in logical pixels.
const double compactButtonHeight = 32;
