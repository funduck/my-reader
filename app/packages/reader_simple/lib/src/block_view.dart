import 'dart:async';
import 'dart:typed_data';

import 'package:core/domain_books.dart';
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
      span: inlineSpan(inlines, style, highlights: local),
      style: textStyle,
      interactions: interactions,
    );
  }
}

/// Label of the context menu button that translates the selection.
const String translateLabel = 'Translate';

/// A selectable text that reports single taps and a "Translate" choice.
///
/// A tap is reported [kDoubleTapTimeout] after it happened, unless a
/// selection appears first: a double click selects the word and must not also
/// be a tap. A tap that only dismisses an existing selection is not reported.
class _InteractiveText extends StatefulWidget {
  const new({
    required this.target,
    required this.span,
    required this.style,
    required this.interactions,
  });

  final TextTarget target;
  final TextSpan span;
  final TextStyle style;
  final TextInteractions interactions;

  @override
  State<_InteractiveText> createState() => _InteractiveTextState();
}

class _InteractiveTextState extends State<_InteractiveText> {
  Offset? _down;
  bool _selected = false;
  bool _selectedAtDown = false;
  Timer? _pending;

  @override
  void dispose() {
    _pending?.cancel();
    super.dispose();
  }

  void _onTap() {
    final down = _down;
    if (_selectedAtDown || down == null) return;
    final editable = _editable();
    if (editable == null) return;
    final offset = editable.getPositionForPoint(down).offset;
    _pending?.cancel();
    _pending = Timer(kDoubleTapTimeout, () {
      _pending = null;
      widget.interactions.wordTapped(widget.target, offset);
    });
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

  void _onSelectionChanged(TextSelection selection, SelectionChangedCause? _) {
    _selected = !selection.isCollapsed;
    if (_selected) {
      _pending?.cancel();
      _pending = null;
    }
  }

  Widget _menu(BuildContext context, EditableTextState state) {
    final selection = state.textEditingValue.selection;
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
    onPointerDown: (event) {
      _down = event.position;
      _selectedAtDown = _selected;
    },
    child: SelectableText.rich(
      widget.span,
      style: widget.style,
      onTap: _onTap,
      onSelectionChanged: _onSelectionChanged,
      contextMenuBuilder: _menu,
    ),
  );
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
