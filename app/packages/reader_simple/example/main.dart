// Example: SimpleReaderEngine on a FakeOpenedBook.
//
// Run from app/packages/reader_simple:
//   flutter run -d macos -t example/main.dart
import 'dart:async';

import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_api/reader_api.dart';
import 'package:reader_simple/reader_simple.dart';

const _body =
    'The quick brown fox jumps over the lazy dog while the old reader '
    'turns another page of a long book.';

String _chapter(int number) =>
    [for (var p = 1; p <= 30; p++) 'Chapter $number, paragraph $p. $_body']
        .join('\n\n');

void main() => runApp(const ExampleApp());

/// The example application.
class ExampleApp extends StatelessWidget {
  /// Creates the application.
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(title: 'reader_simple example', home: ExampleScreen());
}

/// A reader with controls for font size and theme.
class ExampleScreen extends StatefulWidget {
  /// Creates the screen.
  const new({super.key});

  @override
  State<ExampleScreen> createState() => _ExampleScreenState();
}

class _ExampleScreenState extends State<ExampleScreen> {
  final _engine = SimpleReaderEngine();
  var _settings = const ReaderSettings();
  var _ready = false;

  @override
  void initState() {
    super.initState();
    final book = FakeOpenedBook(
      chapters: [for (var c = 1; c <= 3; c++) _chapter(c)],
    );
    unawaited(_open(book));
  }

  Future<void> _open(OpenedBook book) async {
    await _engine.load(book);
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    unawaited(_engine.dispose());
    super.dispose();
  }

  void _apply(ReaderSettings settings) {
    setState(() => _settings = settings);
    _engine.applySettings(settings);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('reader_simple'),
      actions: [
        TextButton(
          onPressed: () =>
              _apply(_settings.copyWith(fontSize: _settings.fontSize + 2)),
          child: const Text('A+'),
        ),
        TextButton(
          onPressed: () =>
              _apply(_settings.copyWith(fontSize: _settings.fontSize - 2)),
          child: const Text('A-'),
        ),
        TextButton(
          onPressed: () => _apply(
            _settings.copyWith(
              theme: _settings.theme == ReaderTheme.light
                  ? ReaderTheme.dark
                  : ReaderTheme.light,
            ),
          ),
          child: const Text('Theme'),
        ),
      ],
    ),
    body: _ready ? Builder(builder: _engine.buildView) : const SizedBox(),
  );
}
