// Generator of minimal EPUB fixtures (EPUB 2 and EPUB 3).
//
// Library use (tests):  buildEpub2(), buildEpub3(), buildZip(entries).
// Command line:         dart run test/fixtures/build.dart [output-dir]
// writes epub2.epub and epub3.epub into the directory (default: this folder),
// where the tests pick them up like any real book.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A generated book together with what a correct reader must find in it.
class EpubFixture {
  /// Creates a fixture description.
  const new({
    required this.bytes,
    required this.title,
    required this.author,
    required this.language,
    required this.spinePaths,
    required this.coverPath,
    required this.opfPath,
  });

  /// The EPUB (ZIP) file content.
  final Uint8List bytes;

  /// Expected title, with whitespace collapsed.
  final String title;

  /// Expected author string (several creators joined with ", ").
  final String author;

  /// Expected language tag.
  final String language;

  /// Expected container entry names of the spine, in reading order.
  final List<String> spinePaths;

  /// Expected cover entry name.
  final String coverPath;

  /// Entry name of the package document.
  final String opfPath;
}

/// Bytes of a 1x1 PNG used as a cover.
final Uint8List coverPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/'
  'iZk9HQAAAABJRU5ErkJggg==',
);

/// Zips [entries] (name to bytes or string) into a ZIP file.
///
/// The `mimetype` entry, when present, goes first and is stored uncompressed,
/// as the EPUB specification requires.
Uint8List buildZip(Map<String, Object> entries) {
  final archive = Archive();
  final names = entries.keys.toList()
    ..sort((a, b) => a == 'mimetype' ? -1 : (b == 'mimetype' ? 1 : 0));
  for (final name in names) {
    final data = entries[name]!;
    final bytes = data is String ? utf8.encode(data) : data as List<int>;
    final file = ArchiveFile.bytes(name, bytes);
    if (name == 'mimetype') file.compression = CompressionType.none;
    archive.add(file);
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _container(String opfPath) =>
    '''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="$opfPath" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';

String _xhtml(String title, String text) =>
    '''
<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>$title</title></head>
<body><h1>$title</h1><p>$text</p></body></html>''';

/// EPUB 2: OPF in `OEBPS/`, chapters in a subfolder, NCX, cover via
/// `<meta name="cover">`, two creators, a percent-encoded file name, an
/// item with `linear="no"` and a spine reference missing from the manifest.
EpubFixture buildEpub2() {
  const opf = '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>A Tale of
      Two Fixtures</dc:title>
    <dc:creator opf:role="aut">Ann Author</dc:creator>
    <dc:creator opf:role="aut">Ben Writer</dc:creator>
    <dc:language>en</dc:language>
    <dc:identifier id="id">urn:uuid:epub2-fixture</dc:identifier>
    <meta name="cover" content="cover-img"/>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="c1" href="text/one.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="text/Chapter%20Two.xhtml" media-type="application/xhtml+xml"/>
    <item id="c3" href="text/three.xhtml" media-type="application/xhtml+xml"/>
    <item id="cover-img" href="images/cover.png" media-type="image/png"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="c1"/>
    <itemref idref="c2"/>
    <itemref idref="ghost"/>
    <itemref idref="c3" linear="no"/>
  </spine>
</package>''';
  final cover = Uint8List.fromList(coverPng);
  final bytes = buildZip({
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': _container('OEBPS/content.opf'),
    'OEBPS/content.opf': opf,
    'OEBPS/toc.ncx': '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"/>',
    'OEBPS/text/one.xhtml': _xhtml('One', 'First chapter.'),
    'OEBPS/text/Chapter Two.xhtml': _xhtml('Two', 'Second chapter.'),
    'OEBPS/text/three.xhtml': _xhtml('Three', 'Third chapter.'),
    'OEBPS/images/cover.png': cover,
  });
  return EpubFixture(
    bytes: bytes,
    title: 'A Tale of Two Fixtures',
    author: 'Ann Author, Ben Writer',
    language: 'en',
    spinePaths: const [
      'OEBPS/text/one.xhtml',
      'OEBPS/text/Chapter Two.xhtml',
      'OEBPS/text/three.xhtml',
    ],
    coverPath: 'OEBPS/images/cover.png',
    opfPath: 'OEBPS/content.opf',
  );
}

/// EPUB 3: OPF in `EPUB/pkg/` with `../` hrefs, nav document, cover via
/// `properties="cover-image"`, regional language tag, UTF-8 BOM in the OPF.
EpubFixture buildEpub3() {
  const opf = '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid" xml:lang="en-GB">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:epub3-fixture</dc:identifier>
    <dc:title id="t1">Third Edition Fixture</dc:title>
    <meta refines="#t1" property="title-type">main</meta>
    <dc:creator id="a1">Cora Composer</dc:creator>
    <dc:language>en-GB</dc:language>
    <meta property="dcterms:modified">2024-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="cover" href="../images/cover.png" media-type="image/png" properties="cover-image"/>
    <item id="intro" href="../text/intro.xhtml" media-type="application/xhtml+xml"/>
    <item id="main" href="../text/main.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="intro"/>
    <itemref idref="main"/>
  </spine>
</package>''';
  final bytes = buildZip({
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': _container('EPUB/pkg/package.opf'),
    'EPUB/pkg/package.opf': '﻿$opf',
    'EPUB/pkg/nav.xhtml': _xhtml('Contents', 'nav'),
    'EPUB/images/cover.png': Uint8List.fromList(coverPng),
    'EPUB/text/intro.xhtml': _xhtml('Intro', 'Introduction.'),
    'EPUB/text/main.xhtml': _xhtml('Main', 'Main text.'),
  });
  return EpubFixture(
    bytes: bytes,
    title: 'Third Edition Fixture',
    author: 'Cora Composer',
    language: 'en-GB',
    spinePaths: const ['EPUB/text/intro.xhtml', 'EPUB/text/main.xhtml'],
    coverPath: 'EPUB/images/cover.png',
    opfPath: 'EPUB/pkg/package.opf',
  );
}

/// Writes `epub2.epub` and `epub3.epub` into the directory given as the first
/// argument (default: the folder of this script).
Future<void> main(List<String> args) async {
  final dir = args.isNotEmpty
      ? args.first
      : File.fromUri(Platform.script).parent.path;
  await File('$dir/epub2.epub').writeAsBytes(buildEpub2().bytes);
  await File('$dir/epub3.epub').writeAsBytes(buildEpub3().bytes);
  stdout.writeln('Wrote epub2.epub and epub3.epub to $dir');
}
