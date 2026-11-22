import 'dart:io';

import 'package:core/domain_books.dart';
import 'package:core_testing/core_testing.dart';
import 'package:format_epub/format_epub.dart';
import 'package:test/test.dart';

import 'fixtures/build.dart';

void main() {
  // Fixtures are needed while the groups are declared, so the files are
  // written synchronously here and removed after the run.
  final tmp = Directory.systemTemp.createTempSync('format_epub_contract_');
  tearDownAll(() => tmp.deleteSync(recursive: true));

  String write(String name, List<int> bytes) {
    final file = File('${tmp.path}/$name')..writeAsBytesSync(bytes);
    return file.path;
  }

  final epub2 = buildEpub2();
  final epub3 = buildEpub3();

  formatAdapterContract(
    () => const EpubFormatAdapter(),
    FormatFixtures(
      valid: [
        BookFixture(
          path: write('good2.epub', epub2.bytes),
          metadata: BookMetadata(
            title: epub2.title,
            author: epub2.author,
            language: epub2.language,
          ),
          minChapters: 3,
        ),
        BookFixture(
          path: write('good3.epub', epub3.bytes),
          metadata: BookMetadata(
            title: epub3.title,
            author: epub3.author,
            language: epub3.language,
          ),
          minChapters: 2,
        ),
      ],
      invalid: [
        '${tmp.path}/absent.epub',
        write('empty.epub', []),
        write('text.epub', 'not a zip'.codeUnits),
        write('bad-zip.epub', [0x50, 0x4b, 0x03, 0x04, 1, 2, 3]),
        write(
          'truncated.epub',
          epub2.bytes.sublist(0, epub2.bytes.length ~/ 2),
        ),
        write('no-container.epub', buildZip({'a.txt': 'x'})),
        write(
          'bad-container.epub',
          buildZip({'META-INF/container.xml': '<container><rootfiles>'}),
        ),
        write(
          'no-rootfile.epub',
          buildZip({
            'META-INF/container.xml': '<container><rootfiles/></container>',
          }),
        ),
        write(
          'missing-opf.epub',
          buildZip({
            'META-INF/container.xml': [
              '<container><rootfiles><rootfile full-path="x.opf"/>',
              '</rootfiles></container>',
            ].join(),
          }),
        ),
      ],
    ),
  );
}
