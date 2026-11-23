import 'package:core/domain_books.dart';
import 'package:test/test.dart';

TocEntry _entry(int index, [List<TocEntry> children = const []]) => TocEntry(
  title: 'T$index',
  chapter: ChapterRef(href: 'c$index.xhtml', index: index),
  children: children,
);

void main() {
  group('currentTocEntry', () {
    final flat = [_entry(1), _entry(3), _entry(5)];

    test('exact match', () {
      expect(currentTocEntry(flat, 3), flat[1]);
    });

    test('a nested entry on the same chapter wins over its parent', () {
      final child = _entry(3);
      final toc = [
        _entry(1),
        _entry(3, [child]),
        _entry(5),
      ];
      expect(currentTocEntry(toc, 3), same(child));
    });

    test('a nested entry is chosen over a later sibling not yet reached', () {
      final child = _entry(2);
      final toc = [
        _entry(1, [child]),
        _entry(4),
      ];
      expect(currentTocEntry(toc, 3), same(child));
    });

    test('a chapter outside the table of contents gives the previous', () {
      expect(currentTocEntry(flat, 4), flat[1]);
      expect(currentTocEntry(flat, 99), flat[2]);
    });

    test('before the first entry gives null', () {
      expect(currentTocEntry(flat, 0), isNull);
    });

    test('an empty table of contents gives null', () {
      expect(currentTocEntry(const [], 2), isNull);
    });
  });
}
