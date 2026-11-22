import 'dart:io';

import 'package:core/domain_books.dart';
import 'package:format_epub/format_epub.dart';
import 'package:test/test.dart';

import '../fixtures/build.dart';

const adapter = EpubFormatAdapter();

late Directory tmp;

const _container = '''
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
  <rootfiles><rootfile full-path="OEBPS/content.opf"
    media-type="application/oebps-package+xml"/></rootfiles>
</container>''';

String _opf({
  required String version,
  required String manifest,
  required String spine,
  String spineAttrs = '',
}) =>
    '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="$version">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>T</dc:title>
  </metadata>
  <manifest>$manifest</manifest>
  <spine $spineAttrs>$spine</spine>
</package>''';

String _item(String id, String href, [String props = '']) =>
    '<item id="$id" href="$href" media-type="application/xhtml+xml" '
    '${props.isEmpty ? '' : 'properties="$props"'}/>';

String _page(String body) =>
    '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml">\n'
    '<head><title>x</title></head><body>$body</body></html>';

String _spine(List<String> ids) =>
    [for (final id in ids) '<itemref idref="$id"/>'].join();

Future<EpubBook> _open(String name, Map<String, Object> entries) {
  final file = File('${tmp.path}/$name.epub')
    ..writeAsBytesSync(
      buildZip({
        'mimetype': 'application/epub+zip',
        'META-INF/container.xml': _container,
        ...entries,
      }),
    );
  return adapter.open(file.path);
}

/// Compact text form: `title|href|index`, children indented by two spaces.
List<String> _dump(List<TocEntry> entries, [String indent = '']) => [
  for (final e in entries) ...[
    '$indent${e.title}|${e.chapter.href}|${e.chapter.index}',
    ..._dump(e.children, '$indent  '),
  ],
];

void main() {
  setUpAll(() => tmp = Directory.systemTemp.createTempSync('format_epub_toc_'));
  tearDownAll(() => tmp.deleteSync(recursive: true));

  group('EPUB 3 nav', () {
    test('nested items, fragments, grouping span, relative hrefs', () async {
      final book = await _open('nav', {
        'OEBPS/content.opf': _opf(
          version: '3.0',
          manifest: [
            _item('nav', 'nav/nav.xhtml', 'nav'),
            _item('c1', 'text/ch1.xhtml'),
            _item('c2', 'text/Chapter%202.xhtml'),
            _item('c3', 'text/ch3.xhtml'),
          ].join(),
          spine: _spine(['c1', 'c2', 'c3']),
        ),
        'OEBPS/nav/nav.xhtml': '''
<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<body>
  <nav epub:type="landmarks"><ol><li><a href="../text/ch3.xhtml">Landmark</a></li></ol></nav>
  <nav epub:type="toc" id="toc">
    <h1>Contents</h1>
    <ol>
      <li><a href="../text/ch1.xhtml">Chapter
        One</a>
        <ol>
          <li><a href="../text/ch1.xhtml#sec-a">Section A</a></li>
          <li><a href="../text/ch1.xhtml#sec-b">Section <em>B</em></a>
            <ol><li><a href="../text/ch1.xhtml#deep">Deep</a></li></ol>
          </li>
        </ol>
      </li>
      <li><a href="../text/Chapter%202.xhtml">Chapter Two</a></li>
      <li><span>Part Three</span>
        <ol>
          <li><a href="../text/ch3.xhtml#x">Third</a></li>
          <li><a href="http://example.com/">External</a></li>
          <li><a href="../text/missing.xhtml">Not in spine</a></li>
        </ol>
      </li>
    </ol>
  </nav>
</body></html>''',
        'OEBPS/text/ch1.xhtml': _page('<h1>One</h1>'),
        'OEBPS/text/Chapter 2.xhtml': _page('<h1>Two</h1>'),
        'OEBPS/text/ch3.xhtml': _page('<h1>Three</h1>'),
      });
      expect(_dump(book.toc), [
        'Chapter One|OEBPS/text/ch1.xhtml|0',
        '  Section A|OEBPS/text/ch1.xhtml#sec-a|0',
        '  Section B|OEBPS/text/ch1.xhtml#sec-b|0',
        '    Deep|OEBPS/text/ch1.xhtml#deep|0',
        'Chapter Two|OEBPS/text/Chapter 2.xhtml|1',
        'Part Three|OEBPS/text/ch3.xhtml#x|2',
        '  Third|OEBPS/text/ch3.xhtml#x|2',
      ]);
    });

    test('nav in the generated EPUB 3 fixture without a toc nav falls back '
        'to the spine', () async {
      final fixture = buildEpub3();
      final file = File('${tmp.path}/fx3.epub')
        ..writeAsBytesSync(fixture.bytes);
      final book = await adapter.open(file.path);
      // The fixture nav has no <nav epub:type="toc">.
      expect(_dump(book.toc), [
        'Intro|EPUB/text/intro.xhtml|0',
        'Main|EPUB/text/main.xhtml|1',
      ]);
    });
  });

  group('EPUB 2 NCX', () {
    test('nested navPoints, fragments, label whitespace', () async {
      final book = await _open('ncx', {
        'OEBPS/content.opf': _opf(
          version: '2.0',
          manifest:
              '<item id="ncx" href="toc.ncx" '
              'media-type="application/x-dtbncx+xml"/>'
              '${_item('c1', 'a/one.xhtml')}${_item('c2', 'a/two.xhtml')}',
          spine: '<itemref idref="c1"/><itemref idref="c2"/>',
          spineAttrs: 'toc="ncx"',
        ),
        'OEBPS/toc.ncx': '''
<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <docTitle><text>Book</text></docTitle>
  <navMap>
    <navPoint id="p1" playOrder="1">
      <navLabel><text>  Part
        One </text></navLabel>
      <content src="a/one.xhtml"/>
      <navPoint id="p2" playOrder="2">
        <navLabel><text>One, section</text></navLabel>
        <content src="a/one.xhtml#s1"/>
      </navPoint>
      <navPoint id="p3" playOrder="3">
        <navLabel><text>Gone</text></navLabel>
        <content src="a/nowhere.xhtml"/>
      </navPoint>
    </navPoint>
    <navPoint id="p4" playOrder="4">
      <navLabel><text>Two</text></navLabel>
      <content src="a/two.xhtml#top"/>
    </navPoint>
  </navMap>
</ncx>''',
        'OEBPS/a/one.xhtml': _page('<h1>One</h1>'),
        'OEBPS/a/two.xhtml': _page('<h1>Two</h1>'),
      });
      expect(_dump(book.toc), [
        'Part One|OEBPS/a/one.xhtml|0',
        '  One, section|OEBPS/a/one.xhtml#s1|0',
        'Two|OEBPS/a/two.xhtml#top|1',
      ]);
    });

    test('NCX with an empty navMap falls back to the spine', () async {
      final book = await adapter.open(
        (File(
          '${tmp.path}/fx2.epub',
        )..writeAsBytesSync(buildEpub2().bytes)).path,
      );
      expect(_dump(book.toc), [
        'One|OEBPS/text/one.xhtml|0',
        'Two|OEBPS/text/Chapter Two.xhtml|1',
        'Three|OEBPS/text/three.xhtml|2',
      ]);
    });
  });

  group('no table of contents', () {
    test('one entry per spine item, title from first h1-h3', () async {
      final book = await _open('none', {
        'OEBPS/content.opf': _opf(
          version: '2.0',
          manifest: [
            _item('a', 'a.xhtml'),
            _item('b', 'b.xhtml'),
            _item('c', 'c.xhtml'),
            _item('d', 'd.xhtml'),
            _item('e', 'e.xhtml'),
          ].join(),
          spine: _spine(['a', 'b', 'c', 'd', 'e']),
        ),
        'OEBPS/a.xhtml': _page(
          '<p>intro</p><h2> Second\n level </h2><h1>No</h1>',
        ),
        'OEBPS/b.xhtml': _page('<h4>Too deep</h4><h3>Three <i>x</i></h3>'),
        'OEBPS/c.xhtml': _page('<p>No headings</p>'),
        // Not well-formed XML (HTML entity): regex fallback.
        'OEBPS/d.xhtml':
            '<html><body><h1>Fish&nbsp;&amp;<br> chips</h1></body></html>',
        'OEBPS/e.xhtml': _page('<h1>   </h1>'),
      });
      expect(_dump(book.toc), [
        'Second level|OEBPS/a.xhtml|0',
        'Three x|OEBPS/b.xhtml|1',
        'c|OEBPS/c.xhtml|2',
        'Fish &amp; chips|OEBPS/d.xhtml|3',
        'e|OEBPS/e.xhtml|4',
      ]);
    });

    test('toc is empty-safe: missing nav file falls through to NCX', () async {
      final book = await _open('navmissing', {
        'OEBPS/content.opf': _opf(
          version: '3.0',
          manifest:
              '${_item('nav', 'nav.xhtml', 'nav')}${_item('a', 'a.xhtml')}',
          spine: '<itemref idref="a"/>',
        ),
        'OEBPS/a.xhtml': _page('<h1>Alpha</h1>'),
      });
      expect(_dump(book.toc), ['Alpha|OEBPS/a.xhtml|0']);
    });
  });
}
