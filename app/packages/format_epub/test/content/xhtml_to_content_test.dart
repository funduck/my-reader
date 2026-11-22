import 'dart:io';

import 'package:core/domain_books.dart';
import 'package:format_epub/src/content/xhtml_to_content.dart';
import 'package:test/test.dart';

const chapterPath = 'OEBPS/text/ch1.xhtml';

ChapterContent conv(String body, {String path = chapterPath}) => convertXhtml(
  '<html xmlns="http://www.w3.org/1999/xhtml"><body>$body</body></html>',
  path: path,
);

List<Block> blocks(String body) => conv(body).document.blocks;

TextInline t(String s) => TextInline(s);

/// Readable one-line-per-block form of a document, for the snapshot.
String dump(ChapterContent c) {
  final lines = <String>[];
  void block(Block b, String indent) {
    switch (b) {
      case ParagraphBlock(:final inlines):
        lines.add('${indent}P ${_inlines(inlines)}');
      case HeadingBlock(:final level, :final inlines):
        lines.add('${indent}H$level ${_inlines(inlines)}');
      case QuoteBlock(:final blocks):
        lines.add('${indent}QUOTE');
        for (final inner in blocks) {
          block(inner, '$indent  ');
        }
      case ListBlock(:final ordered, :final items):
        lines.add('$indent${ordered ? 'OL' : 'UL'}');
        for (final item in items) {
          lines.add('$indent  - ${_inlines(item)}');
        }
      case ImageBlock(:final src, :final alt):
        lines.add('${indent}IMG $src alt=${alt == null ? 'null' : '"$alt"'}');
    }
  }

  for (final (i, b) in c.document.blocks.indexed) {
    lines.add('#$i');
    block(b, '  ');
  }
  final ids = c.anchors.entries.map((e) => '${e.key} -> ${e.value}').toList()
    ..sort();
  lines
    ..add('ANCHORS')
    ..addAll(ids.map((s) => '  $s'));
  return '${lines.join('\n')}\n';
}

String _inlines(List<Inline> inlines) => inlines.map(_inline).join(' ');

String _inline(Inline i) => switch (i) {
  TextInline(:final text) => '"${text.replaceAll('\n', r'\n')}"',
  ItalicInline(:final children) => 'I[${_inlines(children)}]',
  BoldInline(:final children) => 'B[${_inlines(children)}]',
  LinkInline(:final href, :final children) => 'A<$href>[${_inlines(children)}]',
};

void main() {
  group('blocks', () {
    test('p', () {
      expect(blocks('<p>Hello world</p>'), [
        ParagraphBlock([t('Hello world')]),
      ]);
    });

    test('h1-h6 keep their level', () {
      for (var level = 1; level <= 6; level++) {
        expect(blocks('<h$level>Title</h$level>'), [
          HeadingBlock(level: level, inlines: [t('Title')]),
        ]);
      }
    });

    test('blockquote holds blocks', () {
      expect(blocks('<blockquote><p>One</p><p>Two</p></blockquote>'), [
        QuoteBlock([
          ParagraphBlock([t('One')]),
          ParagraphBlock([t('Two')]),
        ]),
      ]);
    });

    test('blockquote with loose text gets an anonymous paragraph', () {
      expect(blocks('<blockquote>Just text</blockquote>'), [
        QuoteBlock([
          ParagraphBlock([t('Just text')]),
        ]),
      ]);
    });

    test('ul', () {
      expect(blocks('<ul><li>a</li><li>b</li></ul>'), [
        ListBlock(
          ordered: false,
          items: [
            [t('a')],
            [t('b')],
          ],
        ),
      ]);
    });

    test('ol', () {
      expect(blocks('<ol><li>a</li><li>b</li></ol>'), [
        ListBlock(
          ordered: true,
          items: [
            [t('a')],
            [t('b')],
          ],
        ),
      ]);
    });

    test('li keeps inline markup', () {
      expect(blocks('<ul><li>a <em>b</em></li></ul>'), [
        ListBlock(
          ordered: false,
          items: [
            [
              t('a '),
              ItalicInline([t('b')]),
            ],
          ],
        ),
      ]);
    });

    test('nested list items are flattened after their parent item', () {
      expect(blocks('<ul><li>a<ul><li>a1</li></ul></li><li>b</li></ul>'), [
        ListBlock(
          ordered: false,
          items: [
            [t('a')],
            [t('a1')],
            [t('b')],
          ],
        ),
      ]);
    });

    test('paragraphs inside li are joined with a line break', () {
      expect(blocks('<ol><li><p>one</p><p>two</p></li></ol>'), [
        ListBlock(
          ordered: true,
          items: [
            [t('one\ntwo')],
          ],
        ),
      ]);
    });

    test('empty list and empty paragraph produce nothing', () {
      expect(blocks('<ul></ul><p> </p><p/>'), isEmpty);
    });

    test('img resolves src against the chapter path', () {
      expect(blocks('<img src="../images/a.jpg" alt="A cat"/>'), [
        const ImageBlock(src: 'OEBPS/images/a.jpg', alt: 'A cat'),
      ]);
    });

    test('img without alt or with empty alt has null alt', () {
      expect(blocks('<img src="a.png"/><img src="b.png" alt=""/>'), [
        const ImageBlock(src: 'OEBPS/text/a.png'),
        const ImageBlock(src: 'OEBPS/text/b.png'),
      ]);
    });

    test('img inside p splits the paragraph', () {
      expect(blocks('<p>before<img src="a.png"/>after</p>'), [
        ParagraphBlock([t('before')]),
        const ImageBlock(src: 'OEBPS/text/a.png'),
        ParagraphBlock([t('after')]),
      ]);
    });

    test('img inside em keeps the emphasis on both sides', () {
      expect(blocks('<p><em>x<img src="a.png"/>y</em></p>'), [
        ParagraphBlock([
          ItalicInline([t('x')]),
        ]),
        const ImageBlock(src: 'OEBPS/text/a.png'),
        ParagraphBlock([
          ItalicInline([t('y')]),
        ]),
      ]);
    });

    test('external and data images are dropped', () {
      expect(
        blocks(
          '<img src="http://x.org/a.png"/> '
          '<img src="data:image/png;base64,AAAA"/> '
          '<img/>',
        ),
        isEmpty,
      );
    });

    test('img inside li is dropped', () {
      expect(blocks('<ul><li>a<img src="x.png"/></li></ul>'), [
        ListBlock(
          ordered: false,
          items: [
            [t('a')],
          ],
        ),
      ]);
    });
  });

  group('inlines', () {
    test('em and i make italics', () {
      expect(blocks('<p><em>a</em> <i>b</i></p>'), [
        ParagraphBlock([
          ItalicInline([t('a')]),
          t(' '),
          ItalicInline([t('b')]),
        ]),
      ]);
    });

    test('strong and b make bold', () {
      expect(blocks('<p><strong>a</strong> <b>b</b></p>'), [
        ParagraphBlock([
          BoldInline([t('a')]),
          t(' '),
          BoldInline([t('b')]),
        ]),
      ]);
    });

    test('nesting is kept', () {
      expect(blocks('<p><strong>a <em>b</em></strong></p>'), [
        ParagraphBlock([
          BoldInline([
            t('a '),
            ItalicInline([t('b')]),
          ]),
        ]),
      ]);
    });

    test('br becomes a newline and eats the spaces around it', () {
      expect(blocks('<p>one <br/> two</p>'), [
        ParagraphBlock([t('one\ntwo')]),
      ]);
    });

    test('consecutive br give consecutive newlines', () {
      expect(blocks('<p>one<br/><br/>two</p>'), [
        ParagraphBlock([t('one\n\ntwo')]),
      ]);
    });

    test('trailing br is dropped, leading br kept', () {
      expect(blocks('<p>a<br/></p><p><br/>b</p>'), [
        ParagraphBlock([t('a')]),
        ParagraphBlock([t('\nb')]),
      ]);
    });

    test('a with internal href is resolved against the chapter', () {
      expect(blocks('<p><a href="ch2.xhtml#s1">next</a></p>'), [
        ParagraphBlock([
          LinkInline(href: 'OEBPS/text/ch2.xhtml#s1', children: [t('next')]),
        ]),
      ]);
      expect(blocks('<p><a href="../x/y.xhtml">y</a></p>'), [
        ParagraphBlock([
          LinkInline(href: 'OEBPS/x/y.xhtml', children: [t('y')]),
        ]),
      ]);
    });

    test('a with same-file fragment points at this chapter', () {
      expect(blocks('<p><a href="#fn1">[1]</a></p>'), [
        ParagraphBlock([
          LinkInline(href: '$chapterPath#fn1', children: [t('[1]')]),
        ]),
      ]);
    });

    test('a with external href is kept as written', () {
      expect(blocks('<p><a href="https://a.org/x?y#z">w</a></p>'), [
        ParagraphBlock([
          LinkInline(href: 'https://a.org/x?y#z', children: [t('w')]),
        ]),
      ]);
      expect(blocks('<p><a href="mailto:a@b.c">m</a></p>'), [
        ParagraphBlock([
          LinkInline(href: 'mailto:a@b.c', children: [t('m')]),
        ]),
      ]);
    });

    test('a without href is unwrapped', () {
      expect(blocks('<p><a name="x">text</a></p>'), [
        ParagraphBlock([t('text')]),
      ]);
    });

    test('link wrapping an emphasised word', () {
      expect(blocks('<p><a href="#n"><em>x</em></a></p>'), [
        ParagraphBlock([
          LinkInline(
            href: '$chapterPath#n',
            children: [
              ItalicInline([t('x')]),
            ],
          ),
        ]),
      ]);
    });
  });

  group('unknown tags', () {
    test('inline unknown tags are unwrapped into text', () {
      expect(blocks('<p>a <span class="x">b</span><sup>2</sup> <u>c</u></p>'), [
        ParagraphBlock([t('a b2 c')]),
      ]);
    });

    test('unknown tag inside emphasis stays inside it', () {
      expect(blocks('<p><em>a<span>b</span></em></p>'), [
        ParagraphBlock([
          ItalicInline([t('ab')]),
        ]),
      ]);
    });

    test('div and section are transparent, loose text becomes paragraphs', () {
      expect(
        blocks(
          '<div><section>loose<p>para</p>tail <em>it</em></section></div>',
        ),
        [
          ParagraphBlock([t('loose')]),
          ParagraphBlock([t('para')]),
          ParagraphBlock([
            t('tail '),
            ItalicInline([t('it')]),
          ]),
        ],
      );
    });

    test('table cells become separate paragraphs', () {
      expect(blocks('<table><tr><td>a</td><td>b</td></tr></table>'), [
        ParagraphBlock([t('a')]),
        ParagraphBlock([t('b')]),
      ]);
    });

    test('block element nested in p is separated by a line break', () {
      expect(blocks('<p>a<div>b</div>c</p>'), [
        ParagraphBlock([t('a\nb\nc')]),
      ]);
    });

    test('head, script, style and svg content never reaches the text', () {
      final c = convertXhtml(
        '<html><head><title>T</title><style>p{}</style></head> '
        '<body><script>var x;</script><p>a<svg><title>S</title></svg></p> '
        '</body></html>',
        path: chapterPath,
      );
      expect(c.document.blocks, [
        ParagraphBlock([t('a')]),
      ]);
    });

    test('a document without html/body is converted from its root', () {
      expect(
        convertXhtml('<div><p>x</p></div>', path: chapterPath).document.blocks,
        [
          ParagraphBlock([t('x')]),
        ],
      );
    });

    test('malformed XML throws FormatException', () {
      expect(
        () => convertXhtml('<html><body><p>x</body></html>', path: 'a.xhtml'),
        throwsFormatException,
      );
    });
  });

  group('whitespace', () {
    test('runs of spaces, tabs and newlines collapse to one space', () {
      expect(blocks('<p>a \t\n  b\r\n\fc</p>'), [
        ParagraphBlock([t('a b c')]),
      ]);
    });

    test('leading and trailing whitespace of a block is dropped', () {
      expect(blocks('<p>  \n a  </p>'), [
        ParagraphBlock([t('a')]),
      ]);
    });

    test('space between inline elements survives, once', () {
      expect(blocks('<p><em>a</em> <strong>b</strong></p>'), [
        ParagraphBlock([
          ItalicInline([t('a')]),
          t(' '),
          BoldInline([t('b')]),
        ]),
      ]);
      expect(blocks('<p>a <em> b</em></p>'), [
        ParagraphBlock([
          t('a '),
          ItalicInline([t('b')]),
        ]),
      ]);
    });

    test('trailing space inside the last inline is trimmed', () {
      expect(blocks('<p><em>a </em></p>'), [
        ParagraphBlock([
          ItalicInline([t('a')]),
        ]),
      ]);
    });

    test('non-breaking space is not collapsed', () {
      expect(blocks('<p>a&#160;&#160;b&#160;</p>'), [
        ParagraphBlock([t('a  b ')]),
      ]);
    });

    test('entities are decoded', () {
      expect(blocks('<p>a &amp; b &lt; c &#8212; d &#x2014; e</p>'), [
        ParagraphBlock([t('a & b < c — d — e')]),
      ]);
    });

    test('whitespace between blocks is ignored', () {
      expect(blocks('\n  <p>a</p>\n\n  <p>b</p>\n'), [
        ParagraphBlock([t('a')]),
        ParagraphBlock([t('b')]),
      ]);
    });

    test('CDATA is taken as text', () {
      expect(blocks('<p><![CDATA[a  <b>]]></p>'), [
        ParagraphBlock([t('a <b>')]),
      ]);
    });
  });

  group('anchors', () {
    test('id on a block points to that top-level block', () {
      final c = conv('<p id="a">x</p><h2 id="b">y</h2><p>z</p>');
      expect(c.anchors, {'a': 0, 'b': 1});
    });

    test('id inside a paragraph (a, span) points to its block', () {
      final c = conv(
        '<p>x</p><p>y <span id="s">z</span> <a id="fn" href="#q">1</a></p>',
      );
      expect(c.anchors, {'s': 1, 'fn': 1});
    });

    test('a name works like an id', () {
      expect(conv('<p>x</p><p><a name="n"/>y</p>').anchors, {'n': 1});
    });

    test('id on a container points to its first block', () {
      final c = conv('<p>x</p><div id="d"><p>y</p><p>z</p></div>');
      expect(c.anchors, {'d': 1});
    });

    test('id on an empty element points to the next block', () {
      final c = conv('<p>x</p><div id="e"/><a id="f"/><h1>h</h1>');
      expect(c.anchors, {'e': 1, 'f': 1});
    });

    test('ids inside a quote point to the quote', () {
      final c = conv('<p>x</p><blockquote><p id="q">y</p></blockquote>');
      expect(c.anchors, {'q': 1});
    });

    test('id in a list item points to the list', () {
      final c = conv('<p>x</p><ul><li>a</li><li id="li2">b</li></ul>');
      expect(c.anchors, {'li2': 1});
    });

    test('id after an image inside a paragraph points past the image', () {
      final c = conv('<p><a id="a"/>t<img src="i.png"/><a id="b"/>u</p>');
      expect(c.document.blocks, hasLength(3));
      expect(c.anchors, {'a': 0, 'b': 2});
    });

    test('first occurrence wins; trailing ids are omitted', () {
      final c = conv('<p id="d">x</p><p id="d">y</p><div id="end"/>');
      expect(c.anchors, {'d': 0});
    });
  });

  group('real-book style chapter (stand-in for a real book)', () {
    // No real books can be downloaded in the sandbox, so the fixture is a
    // hand-written chapter in Project Gutenberg EPUB style: wrapper divs,
    // classes, a head with CSS, footnote links, br, entities, odd whitespace.
    final source = File('test/content/chapter_gutenberg.xhtml')
        .readAsStringSync();
    final expected = File('test/content/chapter_gutenberg.snapshot.txt')
        .readAsStringSync();

    test('converted output equals the snapshot exactly', () {
      final c = convertXhtml(source, path: 'OEBPS/text/ch1.xhtml');
      expect(dump(c), expected);
    });
  });
}
