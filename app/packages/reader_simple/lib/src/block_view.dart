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
      align: TextAlign.start,
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

  /// Body text is justified (B-014, item 5); headings pass
  /// [TextAlign.start].
  Widget _text(
    List<Inline> inlines,
    TextStyle textStyle,
    int base, {
    TextAlign align = TextAlign.justify,
  }) {
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
      align: align,
      interactions: interactions,
    );
  }
}

/// Label of the selection toolbar button that translates the selection.
const String translateLabel = 'Translate';

/// Label of the selection toolbar button that copies the selection.
const String copyLabel = 'Copy';

/// A selectable text that reports a ready selection (T-088).
///
/// Selecting is the standard behaviour of [SelectableText]: a hold selects the
/// word and shows the handles, the handles are dragged, a mouse drags or
/// double-clicks. A tap draws nothing. The selection is ready when the pointer
/// goes up after it changed; the intermediate changes are not reported. Then,
/// with `ReaderSettings.translateOnSelect`, the selection is reported at once
/// and collapsed; otherwise the toolbar shows "Translate" and "Copy".
///
/// A double tap with a finger selects nothing (taps will turn pages): for
/// [kDoubleTapTimeout] after a finger tap the text takes no touches, so the
/// second tap never reaches the recognizer of [SelectableText]. A mouse is not
/// affected.
class _InteractiveText extends StatefulWidget {
  const new({
    required this.target,
    required this.inlines,
    required this.readerStyle,
    required this.highlights,
    required this.style,
    required this.align,
    required this.interactions,
  });

  final TextTarget target;
  final List<Inline> inlines;
  final ReaderStyle readerStyle;

  /// Highlight ranges in `target.text`.
  final List<(int, int)> highlights;
  final TextStyle style;
  final TextAlign align;
  final TextInteractions interactions;

  @override
  State<_InteractiveText> createState() => _InteractiveTextState();
}

bool _isFinger(PointerDeviceKind kind) =>
    kind == PointerDeviceKind.touch || kind == PointerDeviceKind.stylus;

class _InteractiveTextState extends State<_InteractiveText> {
  final FocusNode _focus = FocusNode(debugLabel: 'ReaderText');
  bool _selected = false;
  bool _armed = false;

  // Finger tap tracking for the double tap gate.
  final Set<int> _fingers = {};
  Offset? _tapDown;
  bool _tapLong = false;
  Timer? _tapHold;
  Timer? _gate;
  bool _gated = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  // A tap elsewhere takes the focus away and hides the selection, without a
  // selection-changed callback; the selection no longer counts.
  void _onFocus() {
    if (_focus.hasFocus) return;
    _disarm();
    _setSelected(false);
  }

  @override
  void dispose() {
    _disarm();
    _tapHold?.cancel();
    _gate?.cancel();
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    if (_selected) {
      widget.interactions.selectionChanged(widget.target, active: false);
    }
    super.dispose();
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
    if (!_isFinger(event.kind)) return;
    _fingers.add(event.pointer);
    _tapDown = event.position;
    // A second finger is never a tap.
    _tapLong = _fingers.length > 1;
    _tapHold?.cancel();
    _tapHold = Timer(kLongPressTimeout, () => _tapLong = true);
  }

  void _onMove(PointerMoveEvent event) {
    final down = _tapDown;
    if (down == null || !_fingers.contains(event.pointer)) return;
    if ((event.position - down).distance > kTouchSlop) _tapLong = true;
  }

  void _onUp(PointerUpEvent event) {
    if (!_fingers.remove(event.pointer)) return;
    final wasTap = !_tapLong && _fingers.isEmpty;
    _tapHold?.cancel();
    _tapHold = null;
    if (!wasTap) return;
    // A finger tap: the next touch within the double tap time is not for us.
    setState(() => _gated = true);
    _gate?.cancel();
    _gate = Timer(kDoubleTapTimeout, () {
      _gate = null;
      if (mounted) setState(() => _gated = false);
    });
  }

  void _onCancel(PointerCancelEvent event) {
    if (_fingers.remove(event.pointer)) _tapLong = true;
  }

  void _setSelected(bool value) {
    if (_selected == value) return;
    _selected = value;
    widget.interactions.selectionChanged(widget.target, active: value);
  }

  void _onSelectionChanged(
    TextSelection selection,
    SelectionChangedCause? cause,
  ) {
    _setSelected(!selection.isCollapsed);
    if (selection.isCollapsed) {
      _disarm();
    } else {
      _arm();
    }
  }

  // The selection is ready when a pointer goes up after it changed. The handles
  // live in the overlay, outside this widget, so the pointer is watched
  // globally while a selection is waiting.
  void _arm() {
    if (_armed) return;
    _armed = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  void _disarm() {
    if (!_armed) return;
    _armed = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
  }

  void _onPointer(PointerEvent event) {
    if (event is! PointerUpEvent && event is! PointerCancelEvent) return;
    _disarm();
    final mouse = !_isFinger(event.kind);
    // After the gesture recognizers of the same event have finished.
    scheduleMicrotask(() => _ready(mouse: mouse));
  }

  void _ready({required bool mouse}) {
    if (!mounted) return;
    final state = _editableState();
    if (state == null) return;
    final selection = state.textEditingValue.selection;
    if (selection.isCollapsed) return;
    if (widget.readerStyle.settings.translateOnSelect) {
      _translate(state, selection);
    } else if (mouse) {
      // A finger gets the toolbar from the framework.
      state.showToolbar();
    }
  }

  void _translate(EditableTextState state, TextSelection selection) {
    widget.interactions.textSelected(
      widget.target,
      selection.start,
      selection.end,
    );
    state
      ..userUpdateTextEditingValue(
        state.textEditingValue.copyWith(
          selection: const TextSelection.collapsed(offset: 0),
        ),
        SelectionChangedCause.toolbar,
      )
      ..hideToolbar();
  }

  Widget _menu(BuildContext context, EditableTextState state) {
    final selection = state.textEditingValue.selection;
    if (selection.isCollapsed ||
        widget.readerStyle.settings.translateOnSelect) {
      return const SizedBox.shrink();
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: [
        ContextMenuButtonItem(
          label: translateLabel,
          onPressed: () => _translate(state, selection),
        ),
        ContextMenuButtonItem(
          label: copyLabel,
          onPressed: () => state.copySelection(SelectionChangedCause.toolbar),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _onDown,
    onPointerMove: _onMove,
    onPointerUp: _onUp,
    onPointerCancel: _onCancel,
    child: IgnorePointer(
      ignoring: _gated,
      child: _KeepScroll(
        child: SelectableText.rich(
          inlineSpan(
            widget.inlines,
            widget.readerStyle,
            highlights: widget.highlights,
          ),
          style: widget.style,
          textAlign: widget.align,
          focusNode: _focus,
          onSelectionChanged: _onSelectionChanged,
          contextMenuBuilder: _menu,
        ),
      ),
    ),
  );
}

/// Stops the text from scrolling the chapter list when its selection changes
/// (T-107).
///
/// Every selection change makes `EditableText` ask the enclosing scrollables
/// to bring the caret into view (`RenderObject.showOnScreen` with a rect): a
/// post-frame reveal padded by `scrollPadding` and the handle size, and, for
/// a drag, a reveal of the dragged end. In a list of paragraphs that moves
/// the page under the finger: a hold near the screen edge scrolls, a drag that
/// ends below the screen scrolls, and the collapse of the selection after
/// "Translate" (caret to offset 0) jumps back to the start of a paragraph
/// that is partly above the screen. Requests without a rect come from
/// accessibility ("show this node") and pass through.
class _KeepScroll extends SingleChildRenderObjectWidget {
  const new({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderKeepScroll();
}

class _RenderKeepScroll extends RenderProxyBox {
  @override
  void showOnScreen({
    RenderObject? descendant,
    Rect? rect,
    Duration duration = Duration.zero,
    Curve curve = Curves.ease,
  }) {
    if (rect != null) return;
    super.showOnScreen(
      descendant: descendant,
      rect: rect,
      duration: duration,
      curve: curve,
    );
  }
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
