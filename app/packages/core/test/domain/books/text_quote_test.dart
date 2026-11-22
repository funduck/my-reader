import 'package:core/domain_books.dart';
import 'package:test/test.dart';

TextQuote _q(String text, String selected, {int from = 0}) {
  final start = text.indexOf(selected, from);
  return TextQuote.fromText(text, start, start + selected.length);
}

void main() {
  group('TextQuote.fromText', () {
    test('short text: context is everything around the selection', () {
      final q = _q('The quick brown fox', 'quick');
      expect(q.exact, 'quick');
      expect(q.prefix, 'The ');
      expect(q.suffix, ' brown fox');
    });

    test('context is cut to 30 characters on each side', () {
      final before = 'a' * 50;
      final after = 'z' * 50;
      final q = _q('${before}WORD$after', 'WORD');
      expect(q.prefix, 'a' * 30);
      expect(q.suffix, 'z' * 30);
    });

    test('exactly 30 characters of context are kept whole', () {
      final q = _q('${'a' * 30}WORD${'z' * 30}', 'WORD');
      expect(q.prefix, 'a' * 30);
      expect(q.suffix, 'z' * 30);
    });

    test('selection at the start of the text has empty prefix', () {
      final q = TextQuote.fromText('Hello world', 0, 5);
      expect(q.exact, 'Hello');
      expect(q.prefix, '');
      expect(q.suffix, ' world');
    });

    test('selection at the end of the text has empty suffix', () {
      final q = TextQuote.fromText('Hello world', 6, 11);
      expect(q.exact, 'world');
      expect(q.prefix, 'Hello ');
      expect(q.suffix, '');
    });

    test('selection of the whole text has no context', () {
      final q = TextQuote.fromText('Hello', 0, 5);
      expect(q, const TextQuote(exact: 'Hello'));
    });

    test('runs of whitespace and newlines collapse to one space', () {
      final q = _q('one \n\t two  \r\n three   four\n\nfive', 'three');
      expect(q.prefix, 'one two ');
      expect(q.suffix, ' four five');
    });

    test('whitespace inside the selection collapses too', () {
      final q = _q('a   big\n\n  word here', 'big\n\n  word');
      expect(q.exact, 'big word');
    });

    test('context is measured after collapsing whitespace', () {
      final before = '${'x' * 10}${' ' * 40}${'y' * 10}';
      final q = _q('${before}WORD', 'WORD');
      // Collapsed prefix is 10 x + 1 space + 10 y = 21 chars: kept whole.
      expect(q.prefix, '${'x' * 10} ${'y' * 10}');
    });

    test('a cut never splits a surrogate pair', () {
      // Each emoji is two UTF-16 units; 15 of them are 30 units long.
      final emoji = '\u{1F600}' * 16;
      final q = _q('${emoji}WORD$emoji', 'WORD');
      expect(q.prefix, '\u{1F600}' * 15);
      expect(q.suffix, '\u{1F600}' * 15);
    });

    test('empty range throws RangeError', () {
      expect(() => TextQuote.fromText('abc', 1, 1), throwsRangeError);
    });

    test('reversed range throws RangeError', () {
      expect(() => TextQuote.fromText('abc', 2, 1), throwsRangeError);
    });

    test('range outside the text throws RangeError', () {
      expect(() => TextQuote.fromText('abc', -1, 2), throwsRangeError);
      expect(() => TextQuote.fromText('abc', 1, 4), throwsRangeError);
      expect(() => TextQuote.fromText('', 0, 0), throwsRangeError);
    });
  });
}
