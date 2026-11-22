import 'dart:typed_data';

import 'package:core/domain_books.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_style.dart';

/// Loads the bytes of an image by its path inside the book.
typedef ResourceLoader = Future<Uint8List> Function(String href);

/// Builds the span for [inlines]: italic, bold and link runs nest.
TextSpan inlineSpan(List<Inline> inlines, ReaderStyle style) =>
    TextSpan(children: [for (final i in inlines) _span(i, style)]);

InlineSpan _span(Inline inline, ReaderStyle style) => switch (inline) {
  TextInline(:final text) => TextSpan(text: text),
  ItalicInline(:final children) => TextSpan(
    style: const TextStyle(fontStyle: FontStyle.italic),
    children: [for (final c in children) _span(c, style)],
  ),
  BoldInline(:final children) => TextSpan(
    style: const TextStyle(fontWeight: FontWeight.bold),
    children: [for (final c in children) _span(c, style)],
  ),
  LinkInline(:final children) => TextSpan(
    style: TextStyle(
      color: style.link,
      decoration: TextDecoration.underline,
      decorationColor: style.link,
    ),
    children: [for (final c in children) _span(c, style)],
  ),
};

/// One block of a chapter. A block is one list item of the reader, so the
/// reader's position is "block index plus character offset in the block".
class BlockView extends StatelessWidget {
  /// Creates the view of [block]; [loadResource] feeds [ImageBlock]s.
  const new({
    required this.block,
    required this.style,
    required this.loadResource,
    super.key,
  });

  /// The block to draw.
  final Block block;

  /// Colours and sizes.
  final ReaderStyle style;

  /// Source of image bytes.
  final ResourceLoader loadResource;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: style.settings.horizontalPadding,
      vertical: ReaderStyle.blockPadding,
    ),
    child: _content(block),
  );

  Widget _content(Block block) => switch (block) {
    ParagraphBlock(:final inlines) => _text(inlines, style.body),
    HeadingBlock(:final level, :final inlines) => _text(
      inlines,
      style.heading(level),
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
          children: [
            for (final b in blocks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _content(b),
              ),
          ],
        ),
      ),
    ),
    ListBlock(:final ordered, :final items) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
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
              Expanded(child: _text(items[i], style.body)),
            ],
          ),
      ],
    ),
    ImageBlock(:final src, :final alt) => _ImageView(
      src: src,
      alt: alt,
      style: style,
      loadResource: loadResource,
    ),
  };

  Widget _text(List<Inline> inlines, TextStyle textStyle) =>
      SelectableText.rich(inlineSpan(inlines, style), style: textStyle);
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
