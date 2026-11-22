import 'dart:io';

import 'package:core/domain_books.dart';
import 'package:format_epub/format_epub.dart';
import 'package:test/test.dart';

import '../fixtures/build.dart';

const adapter = EpubFormatAdapter();

late Directory tmp;
int counter = 0;

/// Builds an EPUB 3 with [files] (name in `OEBPS/` to body markup, in spine
/// order) and a nav document made of [navItems] (hrefs relative to `OEBPS/`;
/// a title starting with `>` nests it under the previous top-level item).
Future<EpubBook> open(
  Map<String, String> files,
  List<(String, String)> navItems,
) async {
  final manifest = [
    for (final (i, name) in files.keys.indexed)
      '<item id="f$i" href="$name" media-type="application/xhtml+xml"/>',
  ].join();
  final spine = [
    for (var i = 0; i < files.length; i++) '<itemref idref="f$i"/>',
  ].join();
  final nav = StringBuffer();
  for (final (i, (title, href)) in navItems.indexed) {
    if (title.startsWith('>')) continue;
    final kids = [
      for (final (kt, kh)
          in navItems.skip(i + 1).takeWhile((e) => e.$1.startsWith('>')))
        '<li><a href="$kh">${kt.substring(1)}</a></li>',
    ];
    nav.write(
      '<li><a href="$href">$title</a> '
      '${kids.isEmpty ? '' : '<ol>${kids.join()}</ol>'}</li>',
    );
  }
  final bytes = buildZip({
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
        'version="1.0"><rootfiles><rootfile full-path="OEBPS/book.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles></container>',
    'OEBPS/book.opf':
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0"> '
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"> '
        '<dc:title>T</dc:title><dc:language>en</dc:language></metadata> '
        '<manifest><item id="nav" href="nav.xhtml" '
        'media-type="application/xhtml+xml" properties="nav"/>$manifest '
        '</manifest><spine>$spine</spine></package>',
    'OEBPS/nav.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops"><body> '
        '<nav epub:type="toc"><ol>$nav</ol></nav></body></html>',
    for (final MapEntry(:key, :value) in files.entries)
      'OEBPS/$key':
          '<html xmlns="http://www.w3.org/1999/xhtml"><body>$value</body> '
          '</html>',
  });
  final file = File('${tmp.path}/b${counter++}.epub')..writeAsBytesSync(bytes);
  final book = await adapter.open(file.path);
  addTearDown(book.close);
  return book;
}

String plain(List<Inline> inlines) => inlines
    .map(
      (i) => switch (i) {
        TextInline(:final text) => text,
        ItalicInline(:final children) => plain(children),
        BoldInline(:final children) => plain(children),
        LinkInline(:final children) => plain(children),
      },
    )
    .join();

/// One short line per block: `H1 text` or `P text`.
List<String> dump(ContentDocument doc) => [
  for (final b in doc.blocks)
    switch (b) {
      HeadingBlock(:final level, :final inlines) => 'H$level ${plain(inlines)}',
      ParagraphBlock(:final inlines) => 'P ${plain(inlines)}',
      QuoteBlock() => 'QUOTE',
      ListBlock() => 'LIST',
      ImageBlock(:final src) => 'IMG $src',
    },
];

void main() {
  setUpAll(() => tmp = Directory.systemTemp.createTempSync('chapters_'));
  tearDownAll(() => tmp.deleteSync(recursive: true));

  group('several chapters in one file', () {
    late EpubBook book;
    setUp(() async {
      book = await open(
        {
          'all.xhtml':
              '<h1 id="c1">One</h1><p>a1</p><p>a2</p> '
              '<h1 id="c2">Two</h1><p>b1</p> '
              '<div id="c3"/><h1>Three</h1><p>c1</p><p>c2</p>',
        },
        [
          ('One', 'all.xhtml#c1'),
          ('Two', 'all.xhtml#c2'),
          ('Three', 'all.xhtml#c3'),
        ],
      );
    });

    test('spine has one chapter per toc entry', () {
      expect(book.spine.map((c) => c.href), [
        'OEBPS/all.xhtml#c1',
        'OEBPS/all.xhtml#c2',
        'OEBPS/all.xhtml#c3',
      ]);
      expect(book.spine.map((c) => c.index), [0, 1, 2]);
    });

    test('chapter(ref) returns exactly its slice', () async {
      expect(dump(await book.chapter(book.spine[0])), [
        'H1 One',
        'P a1',
        'P a2',
      ]);
      expect(dump(await book.chapter(book.spine[1])), ['H1 Two', 'P b1']);
      expect(dump(await book.chapter(book.spine[2])), [
        'H1 Three',
        'P c1',
        'P c2',
      ]);
    });

    test('toc points to the same chapters', () {
      expect(book.toc.map((e) => e.chapter), book.spine);
    });

    test('a reference to the bare file selects the first chapter', () async {
      final doc = await book.chapter(
        const ChapterRef(href: 'OEBPS/all.xhtml', index: 99),
      );
      expect(dump(doc), ['H1 One', 'P a1', 'P a2']);
    });
  });

  group('one chapter in several files', () {
    late EpubBook book;
    setUp(() async {
      book = await open(
        {
          'a.xhtml': '<h1>A</h1><p>a</p>',
          'b.xhtml': '<p>b</p>',
          'c.xhtml': '<p>c</p>',
          'd.xhtml': '<h1>D</h1><p>d</p>',
          'e.xhtml': '<p>e</p>',
        },
        [('Part one', 'a.xhtml'), ('Part two', 'd.xhtml')],
      );
    });

    test('files are glued until the next toc entry', () async {
      expect(book.spine, hasLength(2));
      expect(dump(await book.chapter(book.spine[0])), [
        'H1 A',
        'P a',
        'P b',
        'P c',
      ]);
      expect(dump(await book.chapter(book.spine[1])), ['H1 D', 'P d', 'P e']);
    });

    test('a file in the middle belongs to the chapter that spans it', () async {
      final doc = await book.chapter(
        const ChapterRef(href: 'OEBPS/b.xhtml', index: 1),
      );
      expect(dump(doc), ['H1 A', 'P a', 'P b', 'P c']);
    });
  });

  group('mixed layout', () {
    late EpubBook book;
    setUp(() async {
      book = await open(
        {
          'cover.xhtml': '<p>Cover</p>',
          'x.xhtml':
              '<p>intro</p><h1 id="s1">S1</h1><p>s1</p> '
              '<h1 id="s2">S2</h1><p>s2</p>',
          'y.xhtml': '<p>y</p><h2 id="s3">S3</h2><p>s3</p>',
          'z.xhtml': '<p>z</p>',
        },
        [
          ('S1', 'x.xhtml#s1'),
          ('>S1 sub', 'x.xhtml#s1'),
          ('S2', 'x.xhtml#s2'),
          ('S3', 'y.xhtml#s3'),
        ],
      );
    });

    test('text before the first entry becomes a leading chapter', () async {
      expect(book.spine, hasLength(4));
      expect(book.spine[0].href, 'OEBPS/cover.xhtml');
      expect(dump(await book.chapter(book.spine[0])), ['P Cover', 'P intro']);
    });

    test('every chapter is exact, none overlaps', () async {
      expect(dump(await book.chapter(book.spine[1])), ['H1 S1', 'P s1']);
      expect(dump(await book.chapter(book.spine[2])), ['H1 S2', 'P s2', 'P y']);
      expect(dump(await book.chapter(book.spine[3])), ['H2 S3', 'P s3', 'P z']);
    });

    test('toc indexes are chapter positions', () {
      expect(book.toc.map((e) => e.chapter.index), [1, 2, 3]);
    });

    test('chapter() accepts a ref taken from the toc', () async {
      for (final e in book.toc) {
        expect(
          await book.chapter(e.chapter),
          await book.chapter(book.spine[e.chapter.index]),
        );
      }
    });

    test('unknown target throws FormatException', () async {
      await expectLater(
        book.chapter(const ChapterRef(href: 'OEBPS/nope.xhtml', index: 0)),
        throwsFormatException,
      );
    });
  });

  test('entries at the same place and out of order are normalised', () async {
    final book = await open(
      {
        'a.xhtml': '<h1 id="p">P</h1><p>p</p><h1 id="q">Q</h1><p>q</p>',
        'b.xhtml': '<p>b</p>',
      },
      [
        ('Q', 'a.xhtml#q'),
        ('P', 'a.xhtml#p'),
        ('P again', 'a.xhtml'),
        ('B', 'b.xhtml'),
      ],
    );
    expect(book.spine.map((c) => c.href), [
      'OEBPS/a.xhtml#p',
      'OEBPS/a.xhtml#q',
      'OEBPS/b.xhtml',
    ]);
    expect(dump(await book.chapter(book.spine[0])), ['H1 P', 'P p']);
    expect(dump(await book.chapter(book.spine[1])), ['H1 Q', 'P q']);
    expect(dump(await book.chapter(book.spine[2])), ['P b']);
  });

  test('named HTML entities are decoded', () async {
    final book = await open(
      {'a.xhtml': '<p>a&nbsp;b &mdash; c &hellip; &amp; &eacute;</p>'},
      [('A', 'a.xhtml')],
    );
    final doc = await book.chapter(book.spine.single);
    expect(dump(doc), ['P a b — c … & é']);
  });

  test('convertXhtml is exported', () {
    final content = convertXhtml(
      '<html xmlns="http://www.w3.org/1999/xhtml"><body> '
      '<p id="x">&nbsp;t</p></body></html>',
      path: 'a.xhtml',
    );
    expect(content.anchors, {'x': 0});
  });
}
