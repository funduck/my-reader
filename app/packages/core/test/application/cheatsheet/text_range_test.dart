import 'dart:typed_data';

import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:test/test.dart';

/// Book whose chapters are built from strings: paragraphs separated by a
/// blank line. `core` may not depend on `core_testing`, so this small fake
/// stands in for its `FakeOpenedBook`.
class _FakeBook implements OpenedBook {
  new(List<List<Block>> chapters)
    : _chapters = chapters,
      spine = [
        for (var i = 0; i < chapters.length; i++)
          ChapterRef(href: 'c$i.xhtml', index: i),
      ];

  factory fromStrings(List<String> chapters) => _FakeBook([
    for (final c in chapters)
      [
        for (final p in c.split('\n\n'))
          if (p.isNotEmpty) ParagraphBlock([TextInline(p)]),
      ],
  ]);

  final List<List<Block>> _chapters;

  @override
  final List<ChapterRef> spine;

  @override
  List<TocEntry> get toc => const [];

  @override
  Future<ContentDocument> chapter(ChapterRef ref) async =>
      ContentDocument(_chapters[ref.index]);

  @override
  Future<Uint8List> resource(String href) => throw UnimplementedError();

  @override
  Future<void> close() async {}
}

const _bookId = BookId('b');

/// A paragraph of [n] words, each the letter [w]: `n * 2 - 1` characters.
String _para(String w, int n) => List.filled(n, w).join(' ');

/// Repeated "w " [times] times, for quote parts.
String _rep(String w, int times) => '$w ' * times;

Locator _at(ChapterRef chapter, double progression) =>
    Locator(book: _bookId, chapter: chapter, progression: progression);

void main() {
  // Chapter with five paragraphs of 150 words (299 characters each, 301 per
  // step with the separator): a b c d e. Text length 5 * 299 + 4 * 2 = 1503.
  final five = _FakeBook.fromStrings([
    ['a', 'b', 'c', 'd', 'e'].map((w) => _para(w, 150)).join('\n\n'),
  ]);
  const ch0 = ChapterRef(href: 'c0.xhtml', index: 0);
  const ch1 = ChapterRef(href: 'c1.xhtml', index: 1);

  group('countWords', () {
    test('counts letter and digit runs, joins apostrophes and hyphens', () {
      expect(countWords(''), 0);
      expect(countWords('  \n '), 0);
      expect(countWords('Hello, world! It was 1984.'), 5);
      expect(countWords("don't well-known rock’n'roll"), 3);
      expect(countWords('-- "quoted" --'), 1);
      expect(countWords('Привет мир'), 2);
    });
  });

  group('selectCheatSheetRange', () {
    test('pages: range inside a chapter, ends on the paragraph that '
        'reaches the budget', () async {
      // Start of paragraph b, budget 300 words: b (150) + c (300).
      final range = await selectCheatSheetRange(
        five,
        from: _at(ch0, 301 / 1503),
        scope: const CheatSheetPages(1),
      );

      expect(
        range,
        CheatSheetRange(
          start: Locator(
            book: _bookId,
            chapter: ch0,
            progression: 301 / 1503,
            quote: TextQuote(
              exact: 'b b b b b b b b b b b b b b b',
              prefix: _rep('a', 15),
              suffix: ' b' * 15,
            ),
          ),
          end: Locator(
            book: _bookId,
            chapter: ch0,
            progression: 901 / 1503,
            quote: TextQuote(
              exact: 'c c c c c c c c c c c c c c c',
              prefix: _rep('c', 15),
              suffix: ' d' * 15,
            ),
          ),
          text: '${_para('b', 150)}\n\n${_para('c', 150)}',
          wordCount: 300,
        ),
      );
    });

    test(
      'pages: a paragraph that crosses the budget is included whole',
      () async {
        final book = _FakeBook.fromStrings([
          [_para('a', 200), _para('b', 200), _para('c', 200)].join('\n\n'),
        ]);
        final range = await selectCheatSheetRange(
          book,
          from: _at(ch0, 0),
          scope: const CheatSheetPages(1),
        );

        expect(range!.text, '${_para('a', 200)}\n\n${_para('b', 200)}');
        expect(range.wordCount, 400);
        // Text length 3 * 399 + 4 = 1201; b ends at 399 + 2 + 399 = 800.
        expect(range.start.progression, 0);
        expect(range.end.progression, 800 / 1201);
      },
    );

    test('start in the middle of a paragraph snaps to its start', () async {
      final fromStart = await selectCheatSheetRange(
        five,
        from: _at(ch0, 301 / 1503),
        scope: const CheatSheetPages(1),
      );
      // Offset 301 + 150 is inside paragraph b; offset 600 is in the
      // separator after b, which still belongs to b.
      for (final offset in [301 + 150, 301 + 298, 600]) {
        final range = await selectCheatSheetRange(
          five,
          from: Locator(
            book: _bookId,
            chapter: ch0,
            progression: offset / 1503,
            quote: const TextQuote(exact: 'b b'),
          ),
          scope: const CheatSheetPages(1),
        );
        expect(range, fromStart, reason: 'offset $offset');
      }
      expect(fromStart!.start.progression, 301 / 1503);
    });

    test('pages: range across a chapter boundary', () async {
      // Two chapters of three paragraphs: a b c | d e f. Each chapter text
      // is 3 * 299 + 2 * 2 = 901 characters.
      final book = _FakeBook.fromStrings([
        ['a', 'b', 'c'].map((w) => _para(w, 150)).join('\n\n'),
        ['d', 'e', 'f'].map((w) => _para(w, 150)).join('\n\n'),
      ]);
      // From the start of c (offset 602): c (150) + d (300).
      final range = await selectCheatSheetRange(
        book,
        from: _at(ch0, 602 / 901),
        scope: const CheatSheetPages(1),
      );

      expect(range!.start.chapter, ch0);
      expect(range.start.progression, 602 / 901);
      expect(range.start.quote!.exact, 'c c c c c c c c c c c c c c c');
      expect(range.end.chapter, ch1);
      expect(range.end.progression, 299 / 901);
      expect(range.end.quote!.exact, 'd d d d d d d d d d d d d d d');
      expect(range.text, '${_para('c', 150)}\n\n${_para('d', 150)}');
      expect(range.wordCount, 300);
    });

    test('pages: the end of the book stops the range', () async {
      final book = _FakeBook.fromStrings([
        ['a', 'b', 'c'].map((w) => _para(w, 150)).join('\n\n'),
        ['d', 'e', 'f'].map((w) => _para(w, 150)).join('\n\n'),
      ]);
      // From the start of e (offset 301) with a budget of 10 pages.
      final range = await selectCheatSheetRange(
        book,
        from: _at(ch1, 301 / 901),
        scope: const CheatSheetPages(10),
      );

      expect(range!.start.chapter, ch1);
      expect(range.start.progression, 301 / 901);
      expect(range.end, ch1End());
      expect(range.text, '${_para('e', 150)}\n\n${_para('f', 150)}');
      expect(range.wordCount, 300);
    });

    test('chapter scope: up to the end of the chapter, not further', () async {
      final book = _FakeBook.fromStrings([
        ['a', 'b', 'c'].map((w) => _para(w, 150)).join('\n\n'),
        ['d', 'e', 'f'].map((w) => _para(w, 150)).join('\n\n'),
      ]);
      final range = await selectCheatSheetRange(
        book,
        from: _at(ch0, 301 / 901),
        scope: const CheatSheetChapter(),
      );

      expect(range!.start.chapter, ch0);
      expect(range.start.progression, 301 / 901);
      expect(range.end.chapter, ch0);
      expect(range.end.progression, 1);
      expect(
        range.end.quote,
        TextQuote(exact: _tail('c'), prefix: _rep('c', 15)),
      );
      expect(range.text, '${_para('b', 150)}\n\n${_para('c', 150)}');
      expect(range.wordCount, 300);
    });

    test('chapter scope ignores the page budget', () async {
      // 2000 words in the chapter, more than one page.
      final book = _FakeBook.fromStrings([
        List.generate(10, (_) => _para('w', 200)).join('\n\n'),
      ]);
      final range = await selectCheatSheetRange(
        book,
        from: _at(ch0, 0),
        scope: const CheatSheetChapter(),
      );
      expect(range!.wordCount, 2000);
    });

    test(
      'empty chapters are skipped for pages and give null for chapter',
      () async {
        final book = _FakeBook([
          [
            const ParagraphBlock([TextInline('a b c')]),
          ],
          [const ImageBlock(src: 'i.png')],
          [
            const ParagraphBlock([TextInline('   ')]),
          ],
          [
            const HeadingBlock(level: 1, inlines: [TextInline('Title')]),
            const QuoteBlock([
              ParagraphBlock([
                BoldInline([TextInline('quoted')]),
                TextInline(' text'),
              ]),
            ]),
            const ListBlock(
              ordered: false,
              items: [
                [TextInline('one')],
                [TextInline('two')],
              ],
            ),
          ],
        ]);
        final pages = await selectCheatSheetRange(
          book,
          from: _at(ch0, 0),
          scope: const CheatSheetPages(1),
        );
        expect(pages!.text, 'a b c\n\nTitle\n\nquoted text\n\none\n\ntwo');
        expect(pages.wordCount, 8);
        expect(pages.end.chapter, const ChapterRef(href: 'c3.xhtml', index: 3));

        final chapter = await selectCheatSheetRange(
          book,
          from: _at(const ChapterRef(href: 'c1.xhtml', index: 1), 0),
          scope: const CheatSheetChapter(),
        );
        expect(chapter, isNull);
      },
    );

    test('unknown chapter gives null', () async {
      final range = await selectCheatSheetRange(
        five,
        from: _at(const ChapterRef(href: 'zzz.xhtml', index: 9), 0),
        scope: const CheatSheetPages(1),
      );
      expect(range, isNull);
    });
  });
}

/// Last 30 characters of paragraph [w] of 150 words, collapsed.
String _tail(String w) => _para(w, 15).substring(0, 29);

/// End locator of the paragraph `f` (last of chapter 1, text length 901).
Locator ch1End() => Locator(
  book: _bookId,
  chapter: const ChapterRef(href: 'c1.xhtml', index: 1),
  progression: 1,
  quote: TextQuote(exact: _tail('f'), prefix: _rep('f', 15)),
);
