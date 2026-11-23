import 'dart:convert';

import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:test/test.dart';

PhraseLookup _phrase({String? sentence = 'He gave up.', String id = 'p1'}) =>
    PhraseLookup(
      id: PhraseLookupId(id),
      text: 'gave up',
      translation: 'сдался',
      provider: const ProviderId('deepl'),
      at: DateTime.utc(2024, 5, 6, 7, 8, 9, 10, 11),
      locator: const Locator(
        book: BookId('b1'),
        chapter: ChapterRef(href: 'c1.xhtml', index: 2),
        progression: 0.5,
      ),
      sentence: sentence,
    );

void main() {
  group('PhraseLookup', () {
    test('JSON round-trips', () {
      final p = _phrase();
      final json = jsonDecode(jsonEncode(p.toJson())) as Map<String, Object?>;
      final back = PhraseLookup.fromJson(json);
      expect(back, p);
      expect(back.at.isUtc, isTrue);
      expect(back.at, p.at);
    });

    test('JSON round-trips without a sentence', () {
      final p = _phrase(sentence: null);
      final json = jsonDecode(jsonEncode(p.toJson())) as Map<String, Object?>;
      expect(PhraseLookup.fromJson(json), p);
      expect(json.containsKey('sentence'), isFalse);
    });

    test('equality and hashCode cover all fields', () {
      expect(_phrase(), _phrase());
      expect(_phrase().hashCode, _phrase().hashCode);
      expect(_phrase(), isNot(_phrase(id: 'p2')));
      expect(_phrase(), isNot(_phrase(sentence: 'other')));
      expect(_phrase(), isNot(_phrase(sentence: null)));
    });
  });

  group('isSingleWord', () {
    test('a word', () => expect(isSingleWord('run'), isTrue));
    test('Unicode letters and digits', () {
      expect(isSingleWord('бежать'), isTrue);
      expect(isSingleWord('42'), isTrue);
    });
    test('apostrophes and hyphens inside', () {
      expect(isSingleWord("don't"), isTrue);
      expect(isSingleWord('don’t'), isTrue);
      expect(isSingleWord('well-known'), isTrue);
    });
    test('edge whitespace and punctuation are ignored', () {
      expect(isSingleWord('word.'), isTrue);
      expect(isSingleWord('  “word,” '), isTrue);
      expect(isSingleWord("(don't)"), isTrue);
    });
    test('two words', () {
      expect(isSingleWord('gave up'), isFalse);
      expect(isSingleWord('well - known'), isFalse);
      expect(isSingleWord('one. two'), isFalse);
    });
    test('empty or no letters', () {
      expect(isSingleWord(''), isFalse);
      expect(isSingleWord('   '), isFalse);
      expect(isSingleWord('...'), isFalse);
    });
    test('dash or apostrophe inside needs letters on both sides', () {
      expect(isSingleWord("a''b"), isFalse);
      expect(isSingleWord('a--b'), isFalse);
    });
  });
}
