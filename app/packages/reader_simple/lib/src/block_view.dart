import 'dart:async';

import 'package:core/domain_books.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import 'interactions.dart';
import 'position.dart';
import 'reader_style.dart';

/// Loads the bytes of an image by its path inside the book.
typedef ResourceLoader = Future<Uint8List> Function(String href);

/// Builds the span for [inlines]: italic, bold and link runs nest.
///
/// [highlights] are `(start, end)` ranges in the text of [inlines] that get
/// the background `style.highlight`.
TextSpan inlineSpan(
  List<Inline> inlines,
  ReaderStyle style, {
  List<(int, int)> highlights = const [],
}) {
  final builder = _SpanBuilder(style, highlights);
  return TextSpan(children: [for (final i in inlines) builder.span(i)]);
}

class _SpanBuilder {
  new(this.style, this.highlights);

  final ReaderStyle style;
  final List<(int, int)> highlights;

  /// Offset in the text of the inlines of the next character.
  int _at = 0;

  InlineSpan span(Inline inline) => switch (inline) {
    TextInline(:final text) => _text(text),
    ItalicInline(:final children) => TextSpan(
      style: const TextStyle(fontStyle: FontStyle.italic),
      children: [for (final c in children) span(c)],
    ),
    BoldInline(:final children) => TextSpan(
      style: const TextStyle(fontWeight: FontWeight.bold),
      children: [for (final c in children) span(c)],
    ),
    LinkInline(:final children) => TextSpan(
      style: TextStyle(
        color: style.link,
        decoration: TextDecoration.underline,
        decorationColor: style.link,
      ),
      children: [for (final c in children) span(c)],
    ),
  };

  InlineSpan _text(String text) {
    final from = _at;
    final to = from + text.length;
    _at = to;
    final cuts = <int>{0, text.length};
    var touched = false;
    for (final (start, end) in highlights) {
      if (end <= from || start >= to) continue;
      touched = true;
      cuts
        ..add((start - from).clamp(0, text.length))
        ..add((end - from).clamp(0, text.length));
    }
    if (!touched) return TextSpan(text: text);
    final sorted = cuts.toList()..sort();
    return TextSpan(
      children: [
        for (var i = 0; i + 1 < sorted.length; i++)
          TextSpan(
            text: text.substring(sorted[i], sorted[i + 1]),
            style: _marked(from + sorted[i], from + sorted[i + 1])
                ? TextStyle(backgroundColor: style.highlight)
                : null,
          ),
      ],
    );
  }

  bool _marked(int start, int end) =>
      highlights.any((r) => r.$1 <= start && end <= r.$2);
}

/// One block of a chapter. A block is one list item of the reader, so the
/// reader's position is "block index plus character offset in the block".
class BlockView extends StatelessWidget {
  /// Creates the view of [block], which has index [index] in its chapter;
  /// [loadResource] feeds [ImageBlock]s, taps and selections go to
  /// [interactions], [highlights] are ranges of the block text to mark.
  const new({
    required this.block,
    required this.index,
    required this.style,
    required this.loadResource,
    required this.interactions,
    this.highlights = const [],
    super.key,
  });

  /// The block to draw.
  final Block block;

  /// Index of [block] in `ContentDocument.blocks`.
  final int index;

  /// Colours and sizes.
  final ReaderStyle style;

  /// Source of image bytes.
  final ResourceLoader loadResource;

  /// Receiver of taps and selections.
  final TextInteractions interactions;

  /// `(start, end)` ranges of `blockText(block)` drawn with a background.
  final List<(int, int)> highlights;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: style.settings.horizontalPadding,
      vertical: ReaderStyle.blockPadding,
    ),
    child: _content(block, 0),
  );

  /// The widget of [block]; [base] is the offset of its text in the text of
  /// the whole block (non-zero for the parts of a quote).
  Widget _content(Block block, int base) => switch (block) {
    ParagraphBlock(:final inlines) => _text(inlines, style.body, base),
    HeadingBlock(:final level, :final inlines) => _text(
      inlines,
      style.heading(level),
      base,
    ),
    QuoteBlock(:final blocks) => DecoratedBox(
      decoration: BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(color: style.muted, width: 3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _quoteParts(blocks, base),
        ),
      ),
    ),
    ListBlock(:final ordered, :final items) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _listItems(ordered, items, base),
    ),
    ImageBlock(:final src, :final alt) => _ImageView(
      src: src,
      alt: alt,
      style: style,
      loadResource: loadResource,
    ),
  };

  List<Widget> _quoteParts(List<Block> blocks, int base) {
    final parts = <Widget>[];
    var at = base;
    for (final b in blocks) {
      parts.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _content(b, at),
        ),
      );
      at += blockText(b).length + 1;
    }
    return parts;
  }

  List<Widget> _listItems(bool ordered, List<List<Inline>> items, int base) {
    final rows = <Widget>[];
    var at = base;
    for (var i = 0; i < items.length; i++) {
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: style.settings.fontSize * 2,
              child: Text(
                ordered ? '${i + 1}.' : '•',
                style: style.body.copyWith(color: style.muted),
              ),
            ),
            Expanded(child: _text(items[i], style.body, at)),
          ],
        ),
      );
      at += inlinesText(items[i]).length + 1;
    }
    return rows;
  }

  Widget _text(List<Inline> inlines, TextStyle textStyle, int base) {
    final text = inlinesText(inlines);
    final local = [
      for (final (start, end) in highlights)
        if (end > base && start < base + text.length)
          (start - base, end - base),
    ];
    return _InteractiveText(
      target: TextTarget(block: index, base: base, text: text),
      inlines: inlines,
      readerStyle: style,
      highlights: local,
      style: textStyle,
      interactions: interactions,
    );
  }
}

/// Label of the context menu button that translates the selection.
const String translateLabel = 'Translate';

/// How long a finger or a mouse button must rest on a word to look it up.
const Duration lookupHoldDuration = Duration(milliseconds: 500);

/// A selectable text that reports a hold on a word and a "Translate" choice.
///
/// Touching a word marks it at once (a mark under the text, separate from
/// `ReaderEngine.highlight`). A hold of [lookupHoldDuration] without moving
/// past [kTouchSlop] is reported as a word tap; releasing earlier or moving
/// only clears the mark.
///
/// A mouse has no long press, so a timer counts the hold. On touch the hold is
/// the long press of [SelectableText] itself: its recognizer wins the gesture
/// arena at [kLongPressTimeout], which equals [lookupHoldDuration], and it
/// cannot be turned off. So the selection it makes is reported as the hold,
/// then collapsed, and the toolbar it shows on release is suppressed.
class _InteractiveText extends StatefulWidget {
  const new({
    required this.target,
    required this.inlines,
    required this.readerStyle,
    required this.highlights,
    required this.style,
    required this.interactions,
  });

  final TextTarget target;
  final List<Inline> inlines;
  final ReaderStyle readerStyle;

  /// Highlight ranges in `target.text`.
  final List<(int, int)> highlights;
  final TextStyle style;
  final TextInteractions interactions;

  @override
  State<_InteractiveText> createState() => _InteractiveTextState();
}

class _InteractiveTextState extends State<_InteractiveText> {
  int? _pointer;
  PointerDeviceKind? _kind;
  Offset? _down;
  int? _downOffset;
  (int, int)? _pressed;
  List<Rect> _pressBoxes = const [];
  bool _selected = false;
  bool _suppressMenu = false;
  Timer? _hold;
  final FocusNode _focus = FocusNode(debugLabel: 'ReaderText');

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  // A tap elsewhere takes the focus away and hides the selection, without a
  // selection-changed callback; the selection no longer counts.
  void _onFocus() {
    if (!_focus.hasFocus) _setSelected(false);
  }

  @override
  void dispose() {
    _hold?.cancel();
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    if (_selected) {
      widget.interactions.selectionChanged(widget.target, active: false);
    }
    super.dispose();
  }

  RenderEditable? _editable() {
    RenderEditable? found;
    void visit(RenderObject o) {
      if (found != null) return;
      if (o is RenderEditable) {
        found = o;
        return;
      }
      o.visitChildren(visit);
    }

    final root = context.findRenderObject();
    if (root != null) visit(root);
    return found;
  }

  EditableTextState? _editableState() {
    EditableTextState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is EditableTextState) {
        found = e.state as EditableTextState;
        return;
      }
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return found;
  }

  void _onDown(PointerDownEvent event) {
    if (_pointer != null) {
      _clearPress();
      _pointer = event.pointer;
      return;
    }
    _pointer = event.pointer;
    _kind = event.kind;
    _down = event.position;
    _suppressMenu = false;
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryButton) {
      return;
    }
    if (_selected) return;
    final editable = _editable();
    if (editable == null) return;
    final offset = editable.getPositionForPoint(event.position).offset;
    final word = wordRangeAt(widget.target.text, offset);
    if (word == null) return;
    _downOffset = offset;
    final box = context.findRenderObject()! as RenderBox;
    final boxes = [
      for (final b in editable.getBoxesForSelection(
        TextSelection(baseOffset: word.$1, extentOffset: word.$2),
      ))
        Rect.fromPoints(
          box.globalToLocal(editable.localToGlobal(b.toRect().topLeft)),
          box.globalToLocal(editable.localToGlobal(b.toRect().bottomRight)),
        ),
    ];
    setState(() {
      _pressed = word;
      _pressBoxes = boxes;
    });
    if (event.kind == PointerDeviceKind.mouse) {
      _hold = Timer(lookupHoldDuration, () {
        _hold = null;
        _lookup();
      });
    }
  }

  void _onMove(PointerMoveEvent event) {
    final down = _down;
    if (event.pointer != _pointer || down == null) return;
    if ((event.position - down).distance > kTouchSlop) _clearPress();
  }

  void _onEnd(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _clearPress();
    _pointer = null;
    _kind = null;
    _down = null;
  }

  void _clearPress() {
    _hold?.cancel();
    _hold = null;
    _downOffset = null;
    if (_pressed != null && mounted) {
      setState(() {
        _pressed = null;
        _pressBoxes = const [];
      });
    }
  }

  void _setSelected(bool value) {
    if (_selected == value) return;
    _selected = value;
    widget.interactions.selectionChanged(widget.target, active: value);
  }

  void _lookup() {
    final offset = _downOffset;
    if (offset == null || _pressed == null) return;
    widget.interactions.wordTapped(widget.target, offset);
  }

  void _onSelectionChanged(
    TextSelection selection,
    SelectionChangedCause? cause,
  ) {
    _setSelected(!selection.isCollapsed);
    if (cause != SelectionChangedCause.longPress ||
        _kind == PointerDeviceKind.mouse ||
        _pressed == null) {
      return;
    }
    _suppressMenu = true;
    _lookup();
    _setSelected(false);
    final state = _editableState();
    if (state == null) return;
    // The selection is being set right now; undo it after this call.
    scheduleMicrotask(() {
      if (!mounted) return;
      state
        ..userUpdateTextEditingValue(
          state.textEditingValue.copyWith(
            selection: const TextSelection.collapsed(offset: 0),
          ),
          SelectionChangedCause.toolbar,
        )
        ..hideToolbar();
    });
  }

  Widget _menu(BuildContext context, EditableTextState state) {
    final selection = state.textEditingValue.selection;
    if (_suppressMenu) return const SizedBox.shrink();
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: [
        ...state.contextMenuButtonItems,
        if (!selection.isCollapsed)
          ContextMenuButtonItem(
            label: translateLabel,
            onPressed: () {
              widget.interactions.textSelected(
                widget.target,
                selection.start,
                selection.end,
              );
              state.hideToolbar();
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _onDown,
    onPointerMove: _onMove,
    onPointerUp: _onEnd,
    onPointerCancel: _onEnd,
    child: Stack(
      children: [
        // Drawn under the text instead of changing its span: a new span makes
        // SelectableText drop the selection, which would break a double tap
        // or a drag that starts on the press.
        // Always present, so the text keeps its place in the tree.
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: PressMarkPainter(
                _pressBoxes,
                widget.readerStyle.highlight,
              ),
            ),
          ),
        ),
        SelectableText.rich(
          inlineSpan(
            widget.inlines,
            widget.readerStyle,
            highlights: widget.highlights,
          ),
          style: widget.style,
          focusNode: _focus,
          onSelectionChanged: _onSelectionChanged,
          contextMenuBuilder: _menu,
        ),
      ],
    ),
  );
}

/// Paints the press mark of a word: [boxes] in the coordinates of the text
/// widget, in [color].
class PressMarkPainter extends CustomPainter {
  /// Creates a painter that fills [boxes] with [color].
  const new(this.boxes, this.color);

  /// Rectangles of the marked word.
  final List<Rect> boxes;

  /// The fill, `ReaderStyle.highlight`.
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (final box in boxes) {
      canvas.drawRect(box, paint);
    }
  }

  @override
  bool shouldRepaint(PressMarkPainter old) =>
      old.color != color || !listEquals(old.boxes, boxes);
}

class _ImageView extends StatefulWidget {
  const new({
    required this.src,
    required this.alt,
    required this.style,
    required this.loadResource,
  });

  final String src;
  final String? alt;
  final ReaderStyle style;
  final ResourceLoader loadResource;

  @override
  State<_ImageView> createState() => _ImageViewState();
}

class _ImageViewState extends State<_ImageView> {
  Future<Uint8List>? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = widget.loadResource(widget.src);
  }

  @override
  void didUpdateWidget(_ImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.src != widget.src) {
      _bytes = widget.loadResource(widget.src);
    }
  }

  @override
  Widget build(BuildContext context) {
    final caption = Text(
      widget.alt ?? '',
      style: widget.style.body.copyWith(color: widget.style.muted),
    );
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) return caption;
        final bytes = snapshot.data;
        if (bytes == null) return const SizedBox(height: 120);
        return Image.memory(
          bytes,
          semanticLabel: widget.alt,
          errorBuilder: (context, error, stack) => caption,
        );
      },
    );
  }
}
