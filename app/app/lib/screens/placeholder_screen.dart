import 'package:material_ui/material_ui.dart';

/// Stub of a screen that a feature will replace.
class PlaceholderScreen extends StatelessWidget {
  /// Creates a stub with [title] and optional [details] lines.
  const new({required this.title, this.details = const [], super.key});

  /// Screen name, shown in the app bar.
  final String title;

  /// Extra lines, e.g. route parameters.
  final List<String> details;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final line in details) Text(line)],
        ),
      ),
    );
  }
}
