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
    const style = ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: WidgetStatePropertyAll(
        EdgeInsetsDirectional.symmetric(horizontal: 12),
      ),
    );
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
