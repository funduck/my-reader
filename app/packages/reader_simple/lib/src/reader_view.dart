import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'block_view.dart';
import 'reader_style.dart';
import 'simple_reader_engine.dart';

/// The widget returned by `SimpleReaderEngine.buildView`.
///
/// Rebuilds when the chapter or the style changes; the list keeps its scroll
/// position across style changes because its key depends on the chapter only.
class ReaderView extends StatelessWidget {
  /// Creates the view of [engine].
  const new({required this.engine, super.key});

  /// The engine whose state is shown.
  final SimpleReaderEngine engine;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([engine.chapter, engine.style]),
    builder: (context, _) {
      final style = engine.style.value;
      final chapter = engine.chapter.value;
      return ColoredBox(
        color: style.background,
        child: chapter == null
            ? const SizedBox.expand()
            : _ChapterList(
                key: ValueKey(chapter.generation),
                engine: engine,
                chapter: chapter,
                style: style,
              ),
      );
    },
  );
}

class _ChapterList extends StatelessWidget {
  const new({
    required this.engine,
    required this.chapter,
    required this.style,
    super.key,
  });

  final SimpleReaderEngine engine;
  final ChapterState chapter;
  final ReaderStyle style;

  @override
  Widget build(BuildContext context) {
    final blocks = chapter.document.blocks;
    final index = chapter.ref?.index ?? 0;
    final hasPrevious = index > 0;
    final hasNext = chapter.ref != null && !chapter.isLast;
    return ScrollablePositionedList.builder(
      itemCount: blocks.length + 2,
      initialScrollIndex: chapter.startBlock + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return _EdgeButton(
            label: 'Previous chapter',
            style: style,
            engine: engine,
            onPressed: hasPrevious ? engine.openPrevious : null,
          );
        }
        if (i == blocks.length + 1) {
          return _EdgeButton(
            label: 'Next chapter',
            style: style,
            engine: engine,
            onPressed: hasNext ? engine.openNext : null,
          );
        }
        return BlockView(
          block: blocks[i - 1],
          style: style,
          loadResource: engine.loadResource,
        );
      },
    );
  }
}

/// The control at the start or end of the list; empty when there is no
/// chapter in that direction.
class _EdgeButton extends StatelessWidget {
  const new({
    required this.label,
    required this.style,
    required this.engine,
    required this.onPressed,
  });

  final String label;
  final ReaderStyle style;
  final SimpleReaderEngine engine;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    final action = onPressed;
    if (action == null) return const SizedBox(height: 48);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          TextButton(
            onPressed: () => unawaited(action()),
            child: Text(label, style: TextStyle(color: style.link)),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: engine.switchFailed,
            builder: (context, failed, _) => failed
                ? Text(
                    'Could not open the chapter',
                    style: TextStyle(color: style.muted),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
