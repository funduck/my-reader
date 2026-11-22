import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'word_at.dart';

/// Position inside the chapter: block index + character offset in the block.
class SpikeLocator {
  const SpikeLocator(this.block, this.offset);
  final int block;
  final int offset;
  @override
  String toString() => 'block=$block offset=$offset';
}

/// Events the spike emits, mirroring ReaderEvent from Architecture-app.md.
class SpikeEvents {
  final lastWord = ValueNotifier<String?>(null); // WordTapped
  final lastSelection = ValueNotifier<String?>(null); // TextSelected
  final lastMenuAction = ValueNotifier<String?>(null); // custom menu button
}

/// Lets tests and the UI ask for the first visible block and jump to one.
class ReaderSpikeController {
  _ReaderSpikeState? _state;
  SpikeLocator? firstVisible() => _state?._firstVisible();
  Future<void> goTo(SpikeLocator l) async => _state?._goTo(l);
}

class ReaderSpike extends StatefulWidget {
  const ReaderSpike({
    super.key,
    required this.paragraphs,
    required this.events,
    this.controller,
  });
  final List<String> paragraphs;
  final SpikeEvents events;
  final ReaderSpikeController? controller;

  @override
  State<ReaderSpike> createState() => _ReaderSpikeState();
}

class _ReaderSpikeState extends State<ReaderSpike> {
  final _scroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  final _keys = <int, GlobalKey>{};
  Offset _lastDown = Offset.zero;

  /// A single tap is reported only after this delay. A double click selects
  /// a word meanwhile, which cancels the pending tap.
  static const tapDelay = Duration(milliseconds: 300);
  Timer? _pendingTap;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
  }

  @override
  void dispose() {
    _pendingTap?.cancel();
    super.dispose();
  }

  GlobalKey _key(int i) => _keys.putIfAbsent(i, GlobalKey.new);

  // ---- item 2: first visible block ---------------------------------------
  SpikeLocator? _firstVisible() {
    final visible =
        _positions.itemPositions.value
            .where((p) => p.itemTrailingEdge > 0)
            .toList()
          ..sort((a, b) => a.index.compareTo(b.index));
    if (visible.isEmpty) return null;
    final first = visible.first;
    final ctx = _key(first.index).currentContext;
    final editable = ctx == null ? null : findRenderEditable(ctx);
    if (editable == null) return SpikeLocator(first.index, 0);
    // Probe inside the text box, on the line that crosses the viewport top.
    // The text itself starts below the item's padding, so a probe at the
    // item's corner would land in the padding and pick the line above.
    final viewportTop = _viewportTop();
    final textTop = editable.localToGlobal(Offset.zero);
    if (textTop.dy >= viewportTop) return SpikeLocator(first.index, 0);
    final offset = editable
        .getPositionForPoint(Offset(textTop.dx + 1, viewportTop + 1))
        .offset;
    return SpikeLocator(first.index, offset);
  }

  double _viewportTop() =>
      (context.findRenderObject()! as RenderBox).localToGlobal(Offset.zero).dy;

  Future<void> _goTo(SpikeLocator l) async {
    // Step 1: bring the block to the top so that it gets built.
    _scroll.jumpTo(index: l.block);
    await WidgetsBinding.instance.endOfFrame;
    // Step 2: shift so the line holding the offset sits at the top. The
    // distance is measured on screen, so the item's padding is included.
    final ctx = _key(l.block).currentContext;
    final editable = ctx == null ? null : findRenderEditable(ctx);
    if (editable == null || l.offset == 0) return;
    final caret = editable.getLocalRectForCaret(TextPosition(offset: l.offset));
    final lineTop = editable.localToGlobal(caret.topLeft).dy;
    final viewport = (context.findRenderObject()! as RenderBox).size.height;
    final shift = lineTop - _viewportTop();
    _scroll.jumpTo(index: l.block, alignment: -shift / viewport);
  }

  // ---- item 4: custom context-menu button --------------------------------
  Widget _menu(BuildContext context, EditableTextState s) {
    final items = [
      ...s.contextMenuButtonItems,
      ContextMenuButtonItem(
        label: 'Translate',
        onPressed: () {
          final sel = s.textEditingValue.selection;
          widget.events.lastMenuAction.value = sel.textInside(
            s.textEditingValue.text,
          );
          s.hideToolbar();
        },
      ),
    ];
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: s.contextMenuAnchors,
      buttonItems: items,
    );
  }

  // ---- item 1: word under tap --------------------------------------------
  void _onTap(int i) {
    // Listener already recorded the pointer position. Listener does not join
    // the gesture arena, so the built-in selection gestures are unaffected.
    final ctx = _key(i).currentContext;
    if (ctx == null) return;
    final off = charOffsetAt(ctx, _lastDown);
    if (off == null) return;
    final r = wordRangeAt(widget.paragraphs[i], off);
    if (r == null) return;
    final word = '${r.textInside(widget.paragraphs[i])}@$i:${r.start}';
    _pendingTap?.cancel();
    _pendingTap = Timer(tapDelay, () => widget.events.lastWord.value = word);
  }

  @override
  Widget build(BuildContext context) {
    return ScrollablePositionedList.builder(
      itemCount: widget.paragraphs.length,
      itemScrollController: _scroll,
      itemPositionsListener: _positions,
      itemBuilder: (ctx, i) => Listener(
        onPointerDown: (e) => _lastDown = e.position,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: SelectableText.rich(
            TextSpan(text: widget.paragraphs[i]),
            key: _key(i),
            style: const TextStyle(fontSize: 18, height: 1.5),
            onTap: () => _onTap(i),
            onSelectionChanged: (sel, cause) {
              if (!sel.isCollapsed) {
                _pendingTap?.cancel();
                widget.events.lastSelection.value = sel.textInside(
                  widget.paragraphs[i],
                );
              }
            },
            contextMenuBuilder: _menu,
          ),
        ),
      ),
    );
  }
}
