import 'dart:convert';

import 'package:core/domain_books.dart';
import 'package:test/test.dart';

Locator _full() => const Locator(
  book: BookId('b1'),
  chapter: ChapterRef(href: 'ch1.xhtml#a', index: 3),
  progression: 0.25,
  quote: TextQuote(exact: 'word', prefix: 'a ', suffix: ' b'),
  engineHint: 'offset:42',
);

void main() {
  group('Locator', () {
    test('equal values are equal and share hashCode', () {
      expect(_full(), _full());
      expect(_full().hashCode, _full().hashCode);
    });

    test('each field takes part in equality', () {
      final base = _full();
      expect(base.copyWith(book: const BookId('b2')), isNot(base));
      expect(
        base.copyWith(chapter: const ChapterRef(href: 'x', index: 3)),
        isNot(base),
      );
      expect(base.copyWith(progression: 0.5), isNot(base));
      expect(
        base.copyWith(quote: const TextQuote(exact: 'other')),
        isNot(base),
      );
      expect(base.copyWith(engineHint: 'x'), isNot(base));
    });

    test('copyWith without arguments gives an equal copy', () {
      expect(_full().copyWith(), _full());
    });

    test('JSON round trip keeps all fields', () {
      final restored = Locator.fromJson(_full().toJson());
      expect(restored, _full());
      expect(restored.hashCode, _full().hashCode);
    });

    test('JSON round trip through a string keeps all fields', () {
      final text = jsonEncode(_full().toJson());
      final decoded = jsonDecode(text) as Map<String, Object?>;
      expect(Locator.fromJson(decoded), _full());
    });

    test('JSON round trip without optional fields', () {
      const bare = Locator(
        book: BookId('b1'),
        chapter: ChapterRef(href: 'c.xhtml', index: 0),
        progression: 0,
      );
      final json = bare.toJson();
      expect(json.containsKey('quote'), isFalse);
      expect(json.containsKey('engineHint'), isFalse);
      expect(Locator.fromJson(json), bare);
    });

    test('integer progression in JSON is read as double', () {
      final json = _full().toJson()..['progression'] = 1;
      expect(Locator.fromJson(json).progression, 1.0);
    });

    test('progression outside 0..1 is rejected', () {
      expect(
        () => Locator(
          book: const BookId('b'),
          chapter: const ChapterRef(href: 'c', index: 0),
          progression: 1.5,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('TextQuote JSON', () {
    test('round trip', () {
      const q = TextQuote(exact: 'e', prefix: 'p', suffix: 's');
      expect(TextQuote.fromJson(q.toJson()), q);
    });

    test('missing prefix and suffix read as empty', () {
      expect(
        TextQuote.fromJson(const {'exact': 'e'}),
        const TextQuote(exact: 'e'),
      );
    });
  });

  group('ChapterRef', () {
    test('equality, copyWith and JSON', () {
      const c = ChapterRef(href: 'a', index: 1);
      expect(c, const ChapterRef(href: 'a', index: 1));
      expect(c.copyWith(index: 2), isNot(c));
      expect(ChapterRef.fromJson(c.toJson()), c);
    });
  });
}
