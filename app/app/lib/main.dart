import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const MyReaderApp());
}

/// Root widget of the app: an empty "My reader" screen for now.
class MyReaderApp extends StatelessWidget {
  /// Creates the root widget.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'My reader',
      home: Scaffold(body: Center(child: Text('My reader'))),
    );
  }
}
