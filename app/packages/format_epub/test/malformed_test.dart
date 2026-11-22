import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/domain_books.dart';
import 'package:format_epub/format_epub.dart';
import 'package:test/test.dart';

import 'fixtures/build.dart';

const adapter = EpubFormatAdapter();

late Directory tmp;
int counter = 0;

/// Concatenates markup pieces (the lints dislike adjacent string literals).
String xml(List<String> parts) => parts.join();

final String containerXml = xml([
  '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"',
  ' version="1.0"><rootfiles><rootfile full-path="book.opf"',
  ' media-type="application/oebps-package+xml"/></rootfiles></container>',
]);

const dc = 'xmlns:dc="http://purl.org/dc/elements/1.1/"';
const opfNs = 'xmlns="http://www.idpf.org/2007/opf"';
const xhtmlType = 'media-type="application/xhtml+xml"';

String opf(List<String> files, {List<String> spineIds = const []}) => xml([
  '<package $opfNs version="2.0"><metadata $dc>',
  '<dc:title>T</dc:title><dc:language>en</dc:language></metadata><manifest>',
  for (final (i, f) in files.indexed) '<item id="f$i" href="$f" $xhtmlType/>',
  '</manifest><spine>',
  for (var i = 0; i < files.length; i++) '<itemref idref="f$i"/>',
  for (final id in spineIds) '<itemref idref="$id"/>',
  '</spine></package>',
]);

/// EPUB 3 package with a nav document and one chapter `a.xhtml`.
final String navOpf = xml([
  '<package $opfNs version="3.0"><metadata $dc><dc:title>T</dc:title>',
  '</metadata><manifest>',
  '<item id="nav" href="nav.xhtml" $xhtmlType properties="nav"/>',
  '<item id="a" href="a.xhtml" $xhtmlType/>',
  '</manifest><spine><itemref idref="a"/></spine></package>',
]);

String page(String body) => xml([
  '<html xmlns="http://www.w3.org/1999/xhtml"><body>',
  body,
  '</body></html>',
]);

String text(ContentDocument doc) => doc.blocks.map((b) => '$b').join('\n');

Future<EpubBook> open(Map<String, Object> entries) async {
  final path = '${tmp.path}/b${counter++}.epub';
  File(path).writeAsBytesSync(buildZip(entries));
  final book = await adapter.open(path);
  addTearDown(book.close);
  return book;
}

/// Only a typed [FormatException] is acceptable as a failure: no RangeError,
/// StateError, TypeError and the like.
Matcher get formatError => throwsA(isA<FormatException>());

void main() {
  setUpAll(() => tmp = Directory.systemTemp.createTempSync('format_epub_bad_'));
  tearDownAll(() => tmp.deleteSync(recursive: true));

  group('malformed chapter XML', () {
    late EpubBook book;
    setUp(() async {
      book = await open({
        'META-INF/container.xml': containerXml,
        'book.opf': opf(['a.xhtml', 'broken.xhtml', 'c.xhtml']),
        'a.xhtml': page('<p>Alpha text.</p>'),
        'broken.xhtml': '<html><body><p>Unclosed <b>tag</p></body>',
        'c.xhtml': page('<p>Gamma text.</p>'),
      });
    });

    test('the book still opens with all three chapters', () {
      expect(book.spine, hasLength(3));
    });

    test('the broken chapter throws FormatException', () async {
      await expectLater(book.chapter(book.spine[1]), formatError);
    });

    test('other chapters are readable after the failure', () async {
      await expectLater(book.chapter(book.spine[1]), formatError);
      expect(text(await book.chapter(book.spine[0])), contains('Alpha'));
      expect(text(await book.chapter(book.spine[2])), contains('Gamma'));
    });

    test('the table of contents is still available', () {
      expect(book.toc, isNotEmpty);
      for (final e in book.toc) {
        expect(e.chapter.index, inInclusiveRange(0, 2));
      }
    });

    test('a file that is not XML at all', () async {
      final b = await open({
        'META-INF/container.xml': containerXml,
        'book.opf': opf(['a.xhtml']),
        'a.xhtml': [0, 1, 2, 255, 254, 60, 60, 62],
      });
      await expectLater(b.chapter(b.spine.single), formatError);
    });

    test('an empty chapter file', () async {
      final b = await open({
        'META-INF/container.xml': containerXml,
        'book.opf': opf(['a.xhtml']),
        'a.xhtml': '',
      });
      await expectLater(b.chapter(b.spine.single), formatError);
    });

    test('malformed nav does not break open; toc falls back', () async {
      final b = await open({
        'META-INF/container.xml': containerXml,
        'book.opf': navOpf,
        'nav.xhtml': '<html><body><nav><ol><li><a href="a.xhtml">',
        'a.xhtml': page('<p>Alpha text.</p>'),
      });
      expect(b.spine, isNotEmpty);
      expect(text(await b.chapter(b.spine.first)), contains('Alpha'));
    });
  });

  group('references to missing files', () {
    test('a spine file absent from the archive', () async {
      final book = await open({
        'META-INF/container.xml': containerXml,
        'book.opf': opf(['a.xhtml', 'gone.xhtml']),
        'a.xhtml': page('<p>Alpha text.</p>'),
      });
      // Whatever the chapter layout, reading ends in text or a typed error;
      // the readable part stays readable.
      var readable = 0;
      for (final ref in book.spine) {
        try {
          if ((await book.chapter(ref)).blocks.isNotEmpty) readable++;
        } on FormatException {
          // typed error is fine
        }
      }
      expect(readable, greaterThan(0));
    });

    test('a spine idref missing from the manifest is dropped', () async {
      final book = await open({
        'META-INF/container.xml': containerXml,
        'book.opf': opf(['a.xhtml'], spineIds: ['ghost']),
        'a.xhtml': page('<p>Alpha text.</p>'),
      });
      expect(book.spine, hasLength(1));
      expect(text(await book.chapter(book.spine.single)), contains('Alpha'));
    });

    test('nav entries pointing to missing files are dropped', () async {
      final book = await open({
        'META-INF/container.xml': containerXml,
        'book.opf': navOpf,
        'nav.xhtml': xml([
          '<html xmlns="http://www.w3.org/1999/xhtml"',
          ' xmlns:epub="http://www.idpf.org/2007/ops"><body>',
          '<nav epub:type="toc"><ol>',
          '<li><a href="a.xhtml">Alpha</a></li>',
          '<li><a href="nowhere.xhtml">Lost</a></li>',
          '<li><a href="http://example.org/x">Web</a></li>',
          '</ol></nav></body></html>',
        ]),
        'a.xhtml': page('<p>Alpha text.</p>'),
      });
      expect([for (final e in book.toc) e.title], ['Alpha']);
      for (final e in book.toc) {
        expect(e.chapter.index, inInclusiveRange(0, book.spine.length - 1));
      }
      expect(text(await book.chapter(book.spine.single)), contains('Alpha'));
    });

    test('chapter() with an unknown href throws FormatException', () async {
      final book = await open({
        'META-INF/container.xml': containerXml,
        'book.opf': opf(['a.xhtml']),
        'a.xhtml': page('<p>Alpha text.</p>'),
      });
      await expectLater(
        book.chapter(const ChapterRef(href: 'nope.xhtml', index: 0)),
        formatError,
      );
      await expectLater(
        book.chapter(const ChapterRef(href: '../../etc/passwd', index: 99)),
        formatError,
      );
      await expectLater(
        book.chapter(const ChapterRef(href: '', index: -1)),
        formatError,
      );
    });

    test('a missing cover file gives null, not an error', () async {
      final book = await open({
        'META-INF/container.xml': containerXml,
        'book.opf': xml([
          '<package $opfNs version="2.0"><metadata $dc>',
          '<dc:title>T</dc:title><meta name="cover" content="img"/>',
          '</metadata><manifest>',
          '<item id="a" href="a.xhtml" $xhtmlType/>',
          '<item id="img" href="cover.png" media-type="image/png"/>',
          '</manifest><spine><itemref idref="a"/></spine></package>',
        ]),
        'a.xhtml': page('<p>Alpha text.</p>'),
      });
      expect(await book.cover(), isNull);
    });
  });

  group('malformed OPF', () {
    Future<void> expectOpenFails(String opfSource) async {
      final path = '${tmp.path}/o${counter++}.epub';
      File(path).writeAsBytesSync(
        buildZip({
          'META-INF/container.xml': containerXml,
          'book.opf': opfSource,
          'a.xhtml': page('<p>x</p>'),
        }),
      );
      await expectLater(adapter.open(path), formatError);
      await expectLater(adapter.readMetadata(path), formatError);
    }

    test('truncated OPF', () => expectOpenFails('<package><metadata>'));

    test(
      'no manifest and no spine',
      () => expectOpenFails('<package $opfNs version="2.0"/>'),
    );

    test(
      'manifest item without href',
      () => expectOpenFails(
        xml([
          '<package $opfNs version="2.0">',
          '<manifest><item id="a" $xhtmlType/></manifest>',
          '<spine><itemref idref="a"/></spine></package>',
        ]),
      ),
    );

    test(
      'itemref without idref',
      () => expectOpenFails(
        xml([
          '<package $opfNs version="2.0"><manifest>',
          '<item id="a" href="a.xhtml" $xhtmlType/></manifest>',
          '<spine><itemref/></spine></package>',
        ]),
      ),
    );
  });

  group('encodings', () {
    const cyrillic = 'Привет, мир';
    const latin = 'café au lait';
    // windows-1251: А..я are 0xC0..0xFF; the sample has no Ё/ё.
    final cp1251 = Uint8List.fromList([
      for (final c in cyrillic.runes)
        if (c < 0x80) c else c - 0x410 + 0xc0,
    ]);
    final latin1Bytes = Uint8List.fromList(latin.runes.toList());

    List<int> doc(String? charset, List<int> body) => [
      ...ascii.encode(
        xml([
          if (charset != null) '<?xml version="1.0" encoding="$charset"?>',
          '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>',
        ]),
      ),
      ...body,
      ...ascii.encode('</p></body></html>'),
    ];

    Future<EpubBook> bookWith(List<int> chapter) => open({
      'META-INF/container.xml': containerXml,
      'book.opf': opf(['a.xhtml']),
      'a.xhtml': chapter,
    });

    Matcher unsupported(String name) => throwsA(
      isA<FormatException>()
          .having((e) => e.message, 'message', contains(name))
          .having((e) => e.message, 'message', contains('a.xhtml')),
    );

    test('ISO-8859-1 declared: exact text', () async {
      final book = await bookWith(doc('ISO-8859-1', latin1Bytes));
      expect(text(await book.chapter(book.spine.single)), contains(latin));
    });

    test('latin1 alias declared: exact text', () async {
      final book = await bookWith(doc('latin1', latin1Bytes));
      expect(text(await book.chapter(book.spine.single)), contains(latin));
    });

    test('windows-1251 declared: FormatException naming it', () async {
      final book = await bookWith(doc('windows-1251', cp1251));
      await expectLater(
        book.chapter(book.spine.single),
        unsupported('windows-1251'),
      );
    });

    test('UTF-8 declared and used', () async {
      final book = await bookWith(doc('utf-8', utf8.encode(cyrillic)));
      expect(text(await book.chapter(book.spine.single)), contains(cyrillic));
    });

    test('no declaration: UTF-8', () async {
      final book = await bookWith(doc(null, utf8.encode(cyrillic)));
      expect(text(await book.chapter(book.spine.single)), contains(cyrillic));
    });

    test('UTF-8 BOM is dropped', () async {
      final book = await bookWith([
        0xef,
        0xbb,
        0xbf,
        ...doc(null, [0x41]),
      ]);
      expect(text(await book.chapter(book.spine.single)), contains('A'));
    });

    test('malformed UTF-8 without declaration: FormatException', () async {
      final book = await bookWith(doc(null, cp1251));
      await expectLater(book.chapter(book.spine.single), unsupported('UTF-8'));
    });

    test('malformed UTF-8 declared as utf-8: FormatException', () async {
      final book = await bookWith(doc('utf-8', cp1251));
      await expectLater(book.chapter(book.spine.single), unsupported('UTF-8'));
    });

    test('UTF-16 by BOM is decoded', () async {
      final source = String.fromCharCodes(doc(null, [0x41]));
      final le = [
        0xff,
        0xfe,
        for (final u in source.codeUnits) ...[u & 0xff, u >> 8],
      ];
      final be = [
        0xfe,
        0xff,
        for (final u in source.codeUnits) ...[u >> 8, u & 0xff],
      ];
      for (final bytes in [le, be]) {
        final book = await bookWith(bytes);
        expect(text(await book.chapter(book.spine.single)), contains('A'));
      }
    });

    test('truncated UTF-16: FormatException', () async {
      final book = await bookWith([0xff, 0xfe, 0x3c]);
      await expectLater(book.chapter(book.spine.single), formatError);
    });

    test('windows-1251 OPF fails with FormatException', () async {
      final path = '${tmp.path}/t${counter++}.epub';
      final opfBytes = [
        ...ascii.encode(
          xml([
            '<?xml version="1.0" encoding="windows-1251"?>',
            '<package $opfNs version="2.0"><metadata $dc><dc:title>',
          ]),
        ),
        ...cp1251,
        ...ascii.encode(
          xml([
            '</dc:title></metadata><manifest>',
            '<item id="a" href="a.xhtml" $xhtmlType/></manifest>',
            '<spine><itemref idref="a"/></spine></package>',
          ]),
        ),
      ];
      File(path).writeAsBytesSync(
        buildZip({
          'META-INF/container.xml': containerXml,
          'book.opf': opfBytes,
          'a.xhtml': page('<p>x</p>'),
        }),
      );
      await expectLater(adapter.readMetadata(path), formatError);
      await expectLater(adapter.open(path), formatError);
    });
  });
}
