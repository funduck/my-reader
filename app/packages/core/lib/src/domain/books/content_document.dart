import 'package:meta/meta.dart';

import 'list_equality.dart';

/// Inline content of a paragraph, heading, quote or list item.
@immutable
sealed class Inline {
  const new();
}

/// Plain text.
@immutable
final class TextInline extends Inline {
  /// Creates a text run.
  const new(this.text);

  /// The text.
  final String text;

  @override
  bool operator ==(Object other) => other is TextInline && other.text == text;

  @override
  int get hashCode => Object.hash(TextInline, text);

  @override
  String toString() => 'TextInline("$text")';
}

/// Italic run of inlines.
@immutable
final class ItalicInline extends Inline {
  /// Creates an italic run.
  const new(this.children);

  /// Content in italics.
  final List<Inline> children;

  @override
  bool operator ==(Object other) =>
      other is ItalicInline && listEquals(other.children, children);

  @override
  int get hashCode => Object.hash(ItalicInline, listHash(children));

  @override
  String toString() => 'ItalicInline($children)';
}

/// Bold run of inlines.
@immutable
final class BoldInline extends Inline {
  /// Creates a bold run.
  const new(this.children);

  /// Content in bold.
  final List<Inline> children;

  @override
  bool operator ==(Object other) =>
      other is BoldInline && listEquals(other.children, children);

  @override
  int get hashCode => Object.hash(BoldInline, listHash(children));

  @override
  String toString() => 'BoldInline($children)';
}

/// Link to [href] with inline content.
@immutable
final class LinkInline extends Inline {
  /// Creates a link.
  const new({required this.href, required this.children});

  /// Link target: a path inside the book or an external URL.
  final String href;

  /// Link label.
  final List<Inline> children;

  @override
  bool operator ==(Object other) =>
      other is LinkInline &&
      other.href == href &&
      listEquals(other.children, children);

  @override
  int get hashCode => Object.hash(LinkInline, href, listHash(children));

  @override
  String toString() => 'LinkInline($href, $children)';
}

/// Block-level element of a chapter.
@immutable
sealed class Block {
  const new();
}

/// Paragraph.
@immutable
final class ParagraphBlock extends Block {
  /// Creates a paragraph.
  const new(this.inlines);

  /// Paragraph content.
  final List<Inline> inlines;

  @override
  bool operator ==(Object other) =>
      other is ParagraphBlock && listEquals(other.inlines, inlines);

  @override
  int get hashCode => Object.hash(ParagraphBlock, listHash(inlines));

  @override
  String toString() => 'ParagraphBlock($inlines)';
}

/// Heading of level 1 (largest) to 6.
@immutable
final class HeadingBlock extends Block {
  /// Creates a heading; [level] must be within 1..6.
  const new({required this.level, required this.inlines})
    : assert(level >= 1 && level <= 6, 'level must be within 1..6');

  /// Heading level, 1..6.
  final int level;

  /// Heading content.
  final List<Inline> inlines;

  @override
  bool operator ==(Object other) =>
      other is HeadingBlock &&
      other.level == level &&
      listEquals(other.inlines, inlines);

  @override
  int get hashCode => Object.hash(HeadingBlock, level, listHash(inlines));

  @override
  String toString() => 'HeadingBlock(h$level, $inlines)';
}

/// Block quotation.
@immutable
final class QuoteBlock extends Block {
  /// Creates a quotation.
  const new(this.blocks);

  /// Quoted blocks.
  final List<Block> blocks;

  @override
  bool operator ==(Object other) =>
      other is QuoteBlock && listEquals(other.blocks, blocks);

  @override
  int get hashCode => Object.hash(QuoteBlock, listHash(blocks));

  @override
  String toString() => 'QuoteBlock($blocks)';
}

/// Bulleted or numbered list.
@immutable
final class ListBlock extends Block {
  /// Creates a list; each item is a list of inlines.
  const new({required this.ordered, required this.items});

  /// Whether items are numbered.
  final bool ordered;

  /// List items.
  final List<List<Inline>> items;

  @override
  bool operator ==(Object other) {
    if (other is! ListBlock || other.ordered != ordered) return false;
    if (other.items.length != items.length) return false;
    for (var i = 0; i < items.length; i++) {
      if (!listEquals(other.items[i], items[i])) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(ListBlock, ordered, Object.hashAll(items.map(listHash)));

  @override
  String toString() => 'ListBlock(ordered: $ordered, $items)';
}

/// Image.
@immutable
final class ImageBlock extends Block {
  /// Creates an image reference.
  const new({required this.src, this.alt});

  /// Path of the image inside the book container.
  final String src;

  /// Alternative text, if the book gives one.
  final String? alt;

  @override
  bool operator ==(Object other) =>
      other is ImageBlock && other.src == src && other.alt == alt;

  @override
  int get hashCode => Object.hash(ImageBlock, src, alt);

  @override
  String toString() => 'ImageBlock($src)';
}

/// Intermediate representation of one chapter: a list of blocks.
@immutable
final class ContentDocument {
  /// Creates a document from [blocks].
  const new(this.blocks);

  /// Chapter content in reading order.
  final List<Block> blocks;

  @override
  bool operator ==(Object other) =>
      other is ContentDocument && listEquals(other.blocks, blocks);

  @override
  int get hashCode => Object.hash(ContentDocument, listHash(blocks));

  @override
  String toString() => 'ContentDocument(${blocks.length} blocks)';
}
