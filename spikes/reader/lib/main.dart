import 'package:material_ui/material_ui.dart';

import 'reader.dart';
import 'text_gen.dart';

void main() => runApp(const SpikeApp());

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final paragraphs = generateChapter();
    final events = SpikeEvents();
    final ctl = ReaderSpikeController();
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: ValueListenableBuilder<String?>(
            valueListenable: events.lastWord,
            builder: (_, w, _) => Text('word: ${w ?? '-'}'),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  debugPrint('first visible: ${ctl.firstVisible()}'),
              child: const Text('pos'),
            ),
          ],
        ),
        body: ReaderSpike(
          paragraphs: paragraphs,
          events: events,
          controller: ctl,
        ),
      ),
    );
  }
}
