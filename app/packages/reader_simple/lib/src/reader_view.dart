import 'dart:async';

import 'package:core/domain_books.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'block_view.dart';
import 'position.dart';
import 'reader_style.dart';
import 'simple_reader_engine.dart';
import 'view_tap.dart';

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
  Widget build(BuildContext context) => ViewTapDetector(
    onTap: engine.viewTapped,
    hasSelection: () => engine.hasSelection,
    child: _content(),
  );

  Widget _content() => ListenableBuilder(
    listenable: Listenable.merge([
      engine.chapter,
      engine.style,
      engine.highlightsListenable,
    ]),
    builder: (context, _) {
      final style = engine.style.value;
      final chapter = engine.chapter.value;
      final settings = style.settings;
      final texture = settings.texture;
      return ColoredBox(
        color: style.background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (texture != null)
              _TextureLayer(
                texture: texture,
                opacity: settings.textureOpacity,
                background: style.background,
              ),
            if (chapter != null)
              _ChapterList(
                key: ValueKey(chapter.generation),
                engine: engine,
                chapter: chapter,
                style: style,
                highlights: engine.highlightsIn(chapter),
              ),
            if (settings.dim > 0)
              IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: settings.dim),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// The tiled texture under the list, outside the scroll.
///
/// The image is blended with the page background by `overlay` (the same by
/// day and by night) and drawn with [opacity]. A mid-grey texture leaves the
/// background unchanged on average; lighter and darker pixels lighten and
/// darken it.
class _TextureLayer extends StatelessWidget {
  const new({
    required this.texture,
    required this.opacity,
    required this.background,
  });

  final ImageProvider texture;
  final double opacity;
  final Color background;

  // `overlay` paints transparent pixels with [background] too, so without the
  // clip the filter floods everything up to the nearest clip.
  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: RepaintBoundary(
      child: ClipRect(
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(background, BlendMode.overlay),
          child: DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: texture,
                repeat: ImageRepeat.repeat,
                opacity: opacity,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ChapterList extends StatefulWidget {
  const new({
    required this.engine,
    required this.chapter,
    required this.style,
    required this.highlights,
    super.key,
  });

  final SimpleReaderEngine engine;
  final ChapterState chapter;
  final ReaderStyle style;
  final Map<int, List<(int, int)>> highlights;

  @override
  State<_ChapterList> createState() => _ChapterListState();
}

class _ChapterListState extends State<_ChapterList> implements ViewportBridge {
  final _scroll = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();
  final GlobalKey _listKey = GlobalKey();
  final Map<int, GlobalKey> _blockKeys = {};
  late final VoidCallback _detach;

  @override
  void initState() {
    super.initState();
    _detach = widget.engine.attachView(this);
    _positions.itemPositions.addListener(widget.engine.positionTouched);
    if (widget.chapter.startOffset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreOffset());
    }
  }

  @override
  void dispose() {
    _positions.itemPositions.removeListener(widget.engine.positionTouched);
    _detach();
    super.dispose();
  }

  int get _blockCount => widget.chapter.document.blocks.length;

  RenderBox? get _listBox {
    final box = _listKey.currentContext?.findRenderObject();
    return box is RenderBox && box.attached ? box : null;
  }

  /// The text of block [block] if it is built.
  RenderEditable? _editable(int block) {
    final render = _blockKeys[block]?.currentContext?.findRenderObject();
    final editable = render == null ? null : _findEditable(render);
    return editable != null && editable.attached ? editable : null;
  }

  @override
  ({BlockPosition position, int? lineEnd})? firstVisible() {
    final box = _listBox;
    if (box == null || _blockCount == 0) return null;
    final top = box.localToGlobal(Offset.zero).dy;
    int? first;
    for (final p in _positions.itemPositions.value) {
      if (p.itemTrailingEdge <= 0) continue;
      if (first == null || p.index < first) first = p.index;
    }
    if (first == null) return null;
    final block = (first - 1).clamp(0, _blockCount - 1);
    final editable = switch (widget.chapter.document.blocks[block]) {
      ParagraphBlock() || HeadingBlock() => _editable(block),
      _ => null,
    };
    if (editable == null) {
      return (position: BlockPosition(block, 0), lineEnd: null);
    }
    final length = widget.chapter.text.blockAt(block).length;
    final textTop = editable.localToGlobal(Offset.zero);
    final offset = textTop.dy >= top
        ? 0
        : editable
              .getPositionForPoint(Offset(textTop.dx + 1, top + 1))
              .offset
              .clamp(0, length);
    final line = editable.getLineAtOffset(TextPosition(offset: offset));
    return (
      position: BlockPosition(block, offset),
      lineEnd: line.extentOffset.clamp(offset, length),
    );
  }

  /// Scrolls so that the line with the start offset of the chapter is at the
  /// top. The block is already first in the list; this measures where the
  /// offset lies inside it and shifts by that much.
  void _restoreOffset() {
    if (!mounted) return;
    final box = _listBox;
    final block = widget.chapter.startBlock;
    final editable = _editable(block);
    if (box == null || box.size.height <= 0 || editable == null) return;
    final caret = editable.getLocalRectForCaret(
      TextPosition(offset: widget.chapter.startOffset),
    );
    final shift =
        editable.localToGlobal(caret.topLeft).dy -
        box.localToGlobal(Offset.zero).dy;
    _scroll.jumpTo(index: block + 1, alignment: -shift / box.size.height);
  }

  @override
  Widget build(BuildContext context) {
    final chapter = widget.chapter;
    final style = widget.style;
    final engine = widget.engine;
    final blocks = chapter.document.blocks;
    final index = chapter.ref?.index ?? 0;
    final hasPrevious = index > 0;
    final hasNext = chapter.ref != null && !chapter.isLast;
    return ScrollablePositionedList.builder(
      key: _listKey,
      itemScrollController: _scroll,
      itemPositionsListener: _positions,
      // On Android 15+ the app draws under the navigation bar: the end of
      // the chapter and the next-chapter control must scroll above it. The
      // top inset keeps the first lines out of the camera cutout when the
      // app draws behind its own bar (T-087).
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        bottom: MediaQuery.paddingOf(context).bottom,
      ),
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
        return KeyedSubtree(
          key: _blockKeys.putIfAbsent(i - 1, GlobalKey.new),
          child: BlockView(
            block: blocks[i - 1],
            index: i - 1,
            style: style,
            loadResource: engine.loadResource,
            interactions: engine,
            highlights: widget.highlights[i - 1] ?? const [],
          ),
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
          Listener(
            onPointerDown: (event) =>
                ViewTapDetector.ignore(context, event.pointer),
            child: TextButton(
              onPressed: () => unawaited(action()),
              child: Text(label, style: TextStyle(color: style.link)),
            ),
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

/// The first `RenderEditable` at or below [root], in paint order.
RenderEditable? _findEditable(RenderObject root) {
  if (root is RenderEditable) return root;
  RenderEditable? found;
  root.visitChildren((child) => found ??= _findEditable(child));
  return found;
}
