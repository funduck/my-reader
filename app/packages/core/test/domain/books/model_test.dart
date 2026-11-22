import 'package:core/domain_books.dart';
import 'package:test/test.dart';

const _ch = ChapterRef(href: 'c.xhtml', index: 0);

void main() {
  test('BookId equality', () {
    expect(const BookId('a'), const BookId('a'));
    expect(const BookId('a').hashCode, const BookId('a').hashCode);
    expect(const BookId('a'), isNot(const BookId('b')));
  });

  test('Book equality and copyWith', () {
    final book = Book(
      id: const BookId('a'),
      metadata: const BookMetadata(title: 'T', author: 'A', language: 'en'),
      format: BookFormat.epub,
      filePath: '/x.epub',
      contentHash: 'h',
      addedAt: DateTime.utc(2026),
    );
    expect(book.copyWith(), book);
    expect(book.copyWith().hashCode, book.hashCode);
    expect(book.copyWith(format: BookFormat.txt), isNot(book));
    expect(
      book.copyWith(metadata: book.metadata.copyWith(title: 'U')),
      isNot(book),
    );
  });

  test('TocEntry compares nested entries deeply', () {
    const a = TocEntry(
      title: 'A',
      chapter: _ch,
      children: [TocEntry(title: 'A1', chapter: _ch)],
    );
    const same = TocEntry(
      title: 'A',
      chapter: _ch,
      children: [TocEntry(title: 'A1', chapter: _ch)],
    );
    const other = TocEntry(
      title: 'A',
      chapter: _ch,
      children: [TocEntry(title: 'A2', chapter: _ch)],
    );
    expect(a, same);
    expect(a.hashCode, same.hashCode);
    expect(a, isNot(other));
  });

  test('ReadingProgress equality', () {
    const loc = Locator(book: BookId('a'), chapter: _ch, progression: 0.1);
    final p = ReadingProgress(
      locator: loc,
      percent: 0.2,
      updatedAt: DateTime.utc(2026),
    );
    expect(p.copyWith(), p);
    expect(p.copyWith(percent: 0.3), isNot(p));
  });

  group('ContentDocument', () {
    ContentDocument build() => const ContentDocument([
      HeadingBlock(level: 1, inlines: [TextInline('Title')]),
      ParagraphBlock([
        TextInline('a '),
        ItalicInline([TextInline('b')]),
        BoldInline([TextInline('c')]),
        LinkInline(href: 'x.xhtml', children: [TextInline('d')]),
      ]),
      QuoteBlock([
        ParagraphBlock([TextInline('q')]),
      ]),
      ListBlock(
        ordered: true,
        items: [
          [TextInline('one')],
          [TextInline('two')],
        ],
      ),
      ImageBlock(src: 'i.png', alt: 'pic'),
    ]);

    test('equal trees are equal with equal hashCode', () {
      expect(build(), build());
      expect(build().hashCode, build().hashCode);
    });

    test('differences deep in the tree are detected', () {
      const a = ContentDocument([
        ListBlock(
          ordered: false,
          items: [
            [TextInline('one')],
          ],
        ),
      ]);
      const b = ContentDocument([
        ListBlock(
          ordered: false,
          items: [
            [TextInline('two')],
          ],
        ),
      ]);
      const c = ContentDocument([
        ListBlock(
          ordered: true,
          items: [
            [TextInline('one')],
          ],
        ),
      ]);
      expect(a, isNot(b));
      expect(a, isNot(c));
    });

    test('heading level takes part in equality', () {
      expect(
        const HeadingBlock(level: 1, inlines: [TextInline('t')]),
        isNot(const HeadingBlock(level: 2, inlines: [TextInline('t')])),
      );
    });
  });
}
