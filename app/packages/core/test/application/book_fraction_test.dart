import 'dart:typed_data';

import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:test/test.dart';

class _Book implements OpenedBook {
  new(this.documents)
    : spine = [
        for (var i = 0; i < documents.length; i++)
          ChapterRef(href: 'c$i.xhtml', index: i),
      ];

  final List<ContentDocument> documents;
  int parsed = 0;

  @override
  final List<ChapterRef> spine;

  @override
  List<TocEntry> get toc => const [];

  @override
  Future<ContentDocument> chapter(ChapterRef ref) async {
    parsed++;
    return documents[ref.index];
  }

  @override
  Future<Uint8List> resource(String href) async => Uint8List(0);

  @override
  Future<void> close() async {}
}

Locator at(int chapter, double progression) => Locator(
  book: const BookId('b'),
  chapter: ChapterRef(href: 'c$chapter.xhtml', index: chapter),
  progression: progression,
);

ContentDocument text(String s) => ContentDocument([
  ParagraphBlock([TextInline(s)]),
]);

void main() {
  group('bookFraction with chapter lengths', () {
    // Chapters of 100, 700 and 200 characters: 1000 in all.
    const lengths = [100, 700, 200];

    double fraction(int chapter, double progression) => bookFraction(
      at(chapter, progression),
      chapterCount: 3,
      chapterLengths: lengths,
    );

    test('chapters weigh what their text weighs', () {
      expect(fraction(1, 0), closeTo(0.1, 1e-9));
      expect(fraction(1, 0.5), closeTo(0.45, 1e-9));
      expect(fraction(2, 0.5), closeTo(0.9, 1e-9));
      // The equal-weight formula would say 0.5 here.
      expect(fraction(1, 0.5), isNot(closeTo(0.5, 0.01)));
    });

    test('start of the book is 0, end of the book is 1', () {
      expect(fraction(0, 0), 0);
      expect(fraction(2, 1), 1);
    });

    test('a chapter past the spine gives 1', () {
      expect(fraction(5, 0.5), 1);
    });

    test('a book without text is 0', () {
      expect(
        bookFraction(
          at(1, 0.5),
          chapterCount: 3,
          chapterLengths: const [0, 0, 0],
        ),
        0,
      );
      expect(
        bookFraction(at(0, 0.5), chapterCount: 0, chapterLengths: const []),
        0,
      );
    });

    test('an empty chapter adds nothing', () {
      expect(
        bookFraction(
          at(2, 0),
          chapterCount: 3,
          chapterLengths: const [50, 0, 50],
        ),
        0.5,
      );
    });
  });

  group('bookFraction without chapter lengths', () {
    test('chapters weigh the same', () {
      expect(bookFraction(at(1, 0.5), chapterCount: 4), 0.375);
      expect(bookFraction(at(0, 0), chapterCount: 4), 0);
      expect(bookFraction(at(3, 1), chapterCount: 4), 1);
    });

    test('is clamped and safe for an empty spine', () {
      expect(bookFraction(at(9, 0.5), chapterCount: 4), 1);
      expect(bookFraction(at(0, 0.2), chapterCount: 0), 0);
    });
  });

  group('measureChapterLengths', () {
    test('counts the text of every chapter in spine order', () async {
      final book = _Book([
        text('Hello'),
        const ContentDocument([
          HeadingBlock(level: 1, inlines: [TextInline('Title')]),
          ParagraphBlock([
            TextInline('ab'),
            BoldInline([TextInline('cd')]),
            ItalicInline([
              LinkInline(href: 'x', children: [TextInline('e')]),
            ]),
          ]),
          QuoteBlock([
            ParagraphBlock([TextInline('quote')]),
          ]),
          ListBlock(
            ordered: false,
            items: [
              [TextInline('one')],
              [TextInline('two')],
            ],
          ),
          ImageBlock(src: 'i.png', alt: 'not counted'),
        ]),
        const ContentDocument([]),
      ]);
      expect(await measureChapterLengths(book), [5, 5 + 5 + 5 + 6, 0]);
    });

    test('a book without chapters gives an empty list', () async {
      expect(await measureChapterLengths(_Book([])), isEmpty);
    });

    test('stops and gives null when asked to', () async {
      final book = _Book([text('a'), text('b'), text('c')]);
      final result = await measureChapterLengths(
        book,
        shouldStop: () => book.parsed >= 1,
      );
      expect(result, isNull);
      expect(book.parsed, 1);
    });
  });
}
