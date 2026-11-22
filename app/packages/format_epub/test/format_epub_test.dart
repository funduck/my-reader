import 'dart:io';
import 'dart:typed_data';

import 'package:core/domain_books.dart';
import 'package:format_epub/format_epub.dart';
import 'package:test/test.dart';

import 'fixtures/build.dart';

const adapter = EpubFormatAdapter();

late Directory tmp;

File write(String name, List<int> bytes) =>
    File('${tmp.path}/$name')..writeAsBytesSync(bytes);

String opfWith({
  String metadata = '',
  String manifest = '',
  String spine = '',
  String version = '2.0',
}) =>
    '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="$version">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">$metadata</metadata>
  <manifest>$manifest</manifest>
  <spine>$spine</spine>
</package>''';

const containerXml = '''
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
  <rootfiles><rootfile full-path="book.opf"
    media-type="application/oebps-package+xml"/></rootfiles>
</container>''';

Uint8List minimalEpub({
  String metadata = '',
  String manifest =
      '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>',
  String spine = '<itemref idref="a"/>',
}) => buildZip({
  'META-INF/container.xml': containerXml,
  'book.opf': opfWith(metadata: metadata, manifest: manifest, spine: spine),
  'a.xhtml': '<html/>',
});

void main() {
  setUpAll(() => tmp = Directory.systemTemp.createTempSync('format_epub_'));
  tearDownAll(() => tmp.deleteSync(recursive: true));

  test('adapter declares the epub format', () {
    expect(adapter.formats, {BookFormat.epub});
  });

  group('generated fixtures', () {
    final cases = {'EPUB 2': buildEpub2(), 'EPUB 3': buildEpub3()};

    for (final MapEntry(key: name, value: fx) in cases.entries) {
      group(name, () {
        late String path;
        setUpAll(
          () => path = write('${name.replaceAll(' ', '')}.epub', fx.bytes).path,
        );

        test('canOpen is true', () async {
          expect(await adapter.canOpen(path), isTrue);
        });

        test('readMetadata returns title, author and language', () async {
          final meta = await adapter.readMetadata(path);
          expect(meta.title, fx.title);
          expect(meta.author, fx.author);
          expect(meta.language, fx.language);
        });

        test('open exposes the same metadata and the OPF path', () async {
          final book = await adapter.open(path);
          addTearDown(book.close);
          expect(book.package.metadata, await adapter.readMetadata(path));
          expect(book.package.path, fx.opfPath);
        });

        test('spine lists the chapters in order with indexes', () async {
          final book = await adapter.open(path);
          addTearDown(book.close);
          expect(book.spine.map((c) => c.href), fx.spinePaths);
          expect(book.spine.map((c) => c.index), [
            for (var i = 0; i < fx.spinePaths.length; i++) i,
          ]);
        });

        test('every spine chapter is readable through resource()', () async {
          final book = await adapter.open(path);
          addTearDown(book.close);
          for (final ref in book.spine) {
            final text = String.fromCharCodes(await book.resource(ref.href));
            expect(text, contains('<html'), reason: ref.href);
          }
        });

        test('cover is found and equals the image bytes', () async {
          final book = await adapter.open(path);
          addTearDown(book.close);
          expect(book.package.coverPath, fx.coverPath);
          expect(await book.cover(), coverPng);
          expect(await adapter.readCover(path), coverPng);
        });

        test('unknown resource throws FormatException', () async {
          final book = await adapter.open(path);
          addTearDown(book.close);
          await expectLater(
            book.resource('nope/missing.png'),
            throwsFormatException,
          );
        });
      });
    }

    test(
      'EPUB 2: names, NCX id, linear=no kept, dangling idref dropped',
      () async {
        final path = write('e2-detail.epub', buildEpub2().bytes).path;
        final book = await adapter.open(path);
        final pkg = book.package;
        expect(pkg.isEpub3, isFalse);
        expect(pkg.ncxItem?.path, 'OEBPS/toc.ncx');
        expect(pkg.navItem, isNull);
        // c3 is linear="no" and still present; "ghost" is not in the manifest.
        expect(book.spine, hasLength(3));
        expect(
          pkg.manifest.keys,
          containsAll(['ncx', 'c1', 'c2', 'c3', 'cover-img']),
        );
      },
    );

    test(
      'EPUB 2: percent-encoded href resolves to the decoded entry',
      () async {
        final book = await adapter.open(
          write('e2-pct.epub', buildEpub2().bytes).path,
        );
        expect(book.spine[1].href, 'OEBPS/text/Chapter Two.xhtml');
        expect(
          await book.resource('OEBPS/text/Chapter%20Two.xhtml'),
          isNotEmpty,
        );
        expect(await book.resource('OEBPS/text/Chapter Two.xhtml'), isNotEmpty);
      },
    );

    test('EPUB 3: nav item, ../ hrefs and BOM in the OPF', () async {
      final book = await adapter.open(
        write('e3-detail.epub', buildEpub3().bytes).path,
      );
      final pkg = book.package;
      expect(pkg.isEpub3, isTrue);
      expect(pkg.navItem?.path, 'EPUB/pkg/nav.xhtml');
      expect(pkg.ncxItem, isNull);
      expect(book.spine.first.href, 'EPUB/text/intro.xhtml');
    });

    test('resource tolerates #fragment, ./ and ../ forms', () async {
      final book = await adapter.open(
        write('e3-forms.epub', buildEpub3().bytes).path,
      );
      final expected = await book.resource('EPUB/text/intro.xhtml');
      for (final form in [
        'EPUB/text/intro.xhtml#part',
        './EPUB/text/intro.xhtml',
        '/EPUB/text/intro.xhtml',
        'EPUB/pkg/../text/intro.xhtml',
      ]) {
        expect(await book.resource(form), expected, reason: form);
      }
    });

    test('resource after close() throws StateError', () async {
      final book = await adapter.open(
        write('e3-close.epub', buildEpub3().bytes).path,
      );
      await book.close();
      await expectLater(
        book.resource('EPUB/text/intro.xhtml'),
        throwsStateError,
      );
    });
  });

  group('every *.epub in test/fixtures', () {
    final files =
        Directory('test/fixtures')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.epub'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    test('the folder scan itself works', () {
      // Real books are optional: the folder may hold none yet.
      expect(files, isA<List<File>>());
    });

    for (final file in files) {
      final name = file.uri.pathSegments.last;
      group(name, () {
        test('canOpen and metadata', () async {
          expect(await adapter.canOpen(file.path), isTrue);
          final meta = await adapter.readMetadata(file.path);
          expect(meta.title.trim(), isNotEmpty);
          expect(meta.language, isNotNull);
        });

        test(
          'spine is non-empty, ordered, and every chapter resolves',
          () async {
            final book = await adapter.open(file.path);
            addTearDown(book.close);
            expect(book.spine, isNotEmpty);
            expect(book.spine.map((c) => c.index), [
              for (var i = 0; i < book.spine.length; i++) i,
            ]);
            for (final ref in book.spine) {
              expect(
                await book.resource(ref.href),
                isNotEmpty,
                reason: ref.href,
              );
            }
          },
        );

        test('a declared cover is readable', () async {
          final book = await adapter.open(file.path);
          addTearDown(book.close);
          if (book.package.coverPath != null) {
            expect(await book.cover(), isNotEmpty);
          }
        });
      });
    }
  });

  group('metadata edge cases', () {
    test('missing title falls back to the file name, rest is null', () async {
      final path = write('Untitled Book.epub', minimalEpub()).path;
      final meta = await adapter.readMetadata(path);
      expect(meta.title, 'Untitled Book');
      expect(meta.author, isNull);
      expect(meta.language, isNull);
    });

    test(
      'first non-empty title and language win; whitespace collapsed',
      () async {
        final path = write(
          'multi.epub',
          minimalEpub(
            metadata: '''
<dc:title>  </dc:title>
<dc:title>  Real   Title </dc:title>
<dc:title>Second</dc:title>
<dc:language>de</dc:language><dc:language>en</dc:language>
<dc:creator>Solo</dc:creator>''',
          ),
        ).path;
        final meta = await adapter.readMetadata(path);
        expect(meta.title, 'Real Title');
        expect(meta.language, 'de');
        expect(meta.author, 'Solo');
      },
    );

    test('no cover declared gives null', () async {
      final book = await adapter.open(
        write('nocover.epub', minimalEpub()).path,
      );
      expect(book.package.coverPath, isNull);
      expect(await book.cover(), isNull);
      expect(
        await adapter.readCover(write('nocover2.epub', minimalEpub()).path),
        isNull,
      );
    });

    test('cover by id convention without metadata', () async {
      final bytes = buildZip({
        'META-INF/container.xml': containerXml,
        'book.opf': opfWith(
          manifest: '''
<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>
<item id="cover" href="c.jpg" media-type="image/jpeg"/>''',
          spine: '<itemref idref="a"/>',
        ),
        'a.xhtml': '<html/>',
        'c.jpg': [1, 2, 3],
      });
      final book = await adapter.open(write('conv.epub', bytes).path);
      expect(await book.cover(), [1, 2, 3]);
    });

    test('a cover meta pointing at a non-image is ignored', () async {
      final bytes = buildZip({
        'META-INF/container.xml': containerXml,
        'book.opf': opfWith(
          metadata: '<meta name="cover" content="a"/>',
          manifest: '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>',
          spine: '<itemref idref="a"/>',
        ),
        'a.xhtml': '<html/>',
      });
      final book = await adapter.open(write('badcover.epub', bytes).path);
      expect(book.package.coverPath, isNull);
    });
  });

  group('invalid files', () {
    Future<void> expectRejected(String path) async {
      expect(await adapter.canOpen(path), isFalse, reason: 'canOpen');
      await expectLater(adapter.readMetadata(path), throwsFormatException);
      await expectLater(adapter.open(path), throwsFormatException);
    }

    test('missing file', () => expectRejected('${tmp.path}/absent.epub'));

    test('empty file', () => expectRejected(write('empty.epub', []).path));

    test(
      'plain text',
      () => expectRejected(write('t.epub', 'not a zip at all'.codeUnits).path),
    );

    test(
      'zip without container.xml',
      () => expectRejected(
        write('nocontainer.epub', buildZip({'a.txt': 'x'})).path,
      ),
    );

    test(
      'container.xml without rootfile',
      () => expectRejected(
        write(
          'norootfile.epub',
          buildZip({
            'META-INF/container.xml': '<container><rootfiles/></container>',
          }),
        ).path,
      ),
    );

    test(
      'malformed container.xml',
      () => expectRejected(
        write(
          'badcontainer.epub',
          buildZip({'META-INF/container.xml': '<container><rootfiles>'}),
        ).path,
      ),
    );

    test(
      'rootfile points to a missing OPF',
      () => expectRejected(
        write(
          'noopf.epub',
          buildZip({'META-INF/container.xml': containerXml}),
        ).path,
      ),
    );

    test('malformed OPF', () async {
      final path = write(
        'badopf.epub',
        buildZip({
          'META-INF/container.xml': containerXml,
          'book.opf': '<package><metadata>',
        }),
      ).path;
      // canOpen only checks that the OPF entry exists.
      expect(await adapter.canOpen(path), isTrue);
      await expectLater(adapter.readMetadata(path), throwsFormatException);
      await expectLater(adapter.open(path), throwsFormatException);
    });

    test('OPF whose root is not <package>', () async {
      final path = write(
        'notpackage.epub',
        buildZip({
          'META-INF/container.xml': containerXml,
          'book.opf': '<html/>',
        }),
      ).path;
      await expectLater(adapter.open(path), throwsFormatException);
    });

    test('empty spine', () async {
      final path = write('emptyspine.epub', minimalEpub(spine: '')).path;
      await expectLater(adapter.open(path), throwsFormatException);
    });

    test('spine referencing only unknown ids', () async {
      final path = write(
        'ghosts.epub',
        minimalEpub(spine: '<itemref idref="zzz"/>'),
      ).path;
      await expectLater(adapter.open(path), throwsFormatException);
    });
  });

  group('path helpers', () {
    test('normalizeEntryPath', () {
      expect(normalizeEntryPath('a/b/../c.xhtml#x'), 'a/c.xhtml');
      expect(normalizeEntryPath('/a//b/./c'), 'a/b/c');
      expect(normalizeEntryPath('a%20b/%D0%B0.xhtml'), 'a b/а.xhtml');
      expect(normalizeEntryPath('100%.xhtml'), '100%.xhtml');
      expect(normalizeEntryPath('../escape'), isNull);
    });

    test('resolveEntryPath', () {
      expect(
        resolveEntryPath('OEBPS/c.opf', 'text/a.xhtml'),
        'OEBPS/text/a.xhtml',
      );
      expect(resolveEntryPath('c.opf', 'a.xhtml'), 'a.xhtml');
      expect(resolveEntryPath('A/B/c.opf', '../x.png'), 'A/x.png');
      expect(resolveEntryPath('A/c.opf', '/root.png'), 'root.png');
      expect(resolveEntryPath('A/c.opf', 'http://x.org/a'), isNull);
      expect(resolveEntryPath('A/c.opf', '../../out'), isNull);
    });
  });
}
