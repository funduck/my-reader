import 'package:core/ports.dart';
import 'package:test/test.dart';
import 'package:text_en/text_en.dart';

typedef _SentenceCase = ({String name, String text, List<(int, int)> spans});

typedef _TokenCase = ({
  String name,
  String text,
  List<(String, int, int)> tokens,
});

_SentenceCase _s(String name, String text, List<(int, int)> spans) =>
    (name: name, text: text, spans: spans);

_TokenCase _t(String name, String text, List<(String, int, int)> tokens) =>
    (name: name, text: text, tokens: tokens);

void main() {
  const analyzer = EnglishTextAnalyzer();

  group('sentences', () {
    final cases = <_SentenceCase>[
      _s('single sentence', 'Hello world.', [(0, 12)]),
      _s('two sentences', 'Hi. Bye.', [(0, 3), (4, 8)]),
      _s('Mr. does not split', 'Mr. Smith left. He sat.', [(0, 15), (16, 23)]),
      _s('Dr. does not split', 'Dr. Who is here.', [(0, 16)]),
      _s('St. does not split', 'St. Paul is old.', [(0, 16)]),
      _s('e.g. does not split', 'Use e.g. apples. Fine.', [(0, 16), (17, 22)]),
      _s('i.e. does not split', 'It is so, i.e. true. Ok.', [
        (0, 20),
        (21, 24),
      ]),
      _s('initials do not split', 'J. K. Rowling wrote it.', [(0, 23)]),
      _s('etc. before capital splits', 'Apples, pears, etc. Then we left.', [
        (0, 19),
        (20, 33),
      ]),
      _s('etc. before lower case joins', 'Apples, etc. are good.', [(0, 22)]),
      _s('U.S. before capital splits', 'He lives in the U.S. He is happy.', [
        (0, 20),
        (21, 33),
      ]),
      _s('a.m. before capital splits', 'We met at 9 a.m. Then left.', [
        (0, 16),
        (17, 27),
      ]),
      _s('pronoun I is not an initial', 'So did I. He left.', [
        (0, 9),
        (10, 18),
      ]),
      _s('ellipsis before capital splits', 'Wait... What?', [(0, 7), (8, 13)]),
      _s('ellipsis before lower case joins', 'Wait... what?', [(0, 13)]),
      _s('ellipsis character splits', 'Well… I see.', [(0, 5), (6, 12)]),
      _s('?! run', 'What?! No way.', [(0, 6), (7, 14)]),
      _s('question, exclamation, period', 'Is it? Yes! Fine.', [
        (0, 6),
        (7, 11),
        (12, 17),
      ]),
      _s('dialogue tag after ! joins', '"Stop!" he said.', [(0, 16)]),
      _s('capital after quote splits', '"Stop!" He ran.', [(0, 7), (8, 15)]),
      _s('quote inside sentence', 'She said, "Go home." Then she left.', [
        (0, 20),
        (21, 35),
      ]),
      _s('curly quote inside sentence', 'She said, “Go home.” Then she left.', [
        (0, 20),
        (21, 35),
      ]),
      _s('two quoted utterances', '"Why?" she asked. "Because."', [
        (0, 17),
        (18, 28),
      ]),
      _s('single-quoted speech', "'Go,' she said. 'Now.'", [(0, 15), (16, 22)]),
      _s('ellipsis inside quote then tag', '"Well..." he said.', [(0, 18)]),
      _s('final quote only', '"Done."', [(0, 7)]),
      _s('period inside parentheses', 'He left (quickly.) She stayed.', [
        (0, 18),
        (19, 30),
      ]),
      _s('decimal number', 'Version 3.5 is out. Update.', [(0, 19), (20, 27)]),
      _s('digit starts a sentence', 'Born in 1984. 2 years later.', [
        (0, 13),
        (14, 28),
      ]),
      _s('blank line splits', 'Chapter One\n\nIt began.', [(0, 11), (13, 22)]),
      _s('CRLF blank line splits', 'One.\r\n\r\nTwo.', [(0, 4), (8, 12)]),
      _s('single newline joins', 'Line one\ncontinues here.', [(0, 24)]),
      _s('no terminator, trimmed', '  Hello there  ', [(2, 13)]),
      _s('empty text', '', []),
      _s('whitespace only', ' \n\t ', []),
      _s('surrogate pair offsets', '\u{1F600} Hi. Bye.', [(0, 6), (7, 11)]),
    ];
    for (final c in cases) {
      test(c.name, () {
        final actual = analyzer
            .sentences(c.text)
            .map((s) => (s.start, s.end))
            .toList();
        expect(actual, c.spans);
      });
    }

    test('spans are SentenceSpan values with exact equality', () {
      expect(analyzer.sentences('Hi. Bye.'), [
        const SentenceSpan(0, 3),
        const SentenceSpan(4, 8),
      ]);
    });
  });

  group('tokens', () {
    final cases = <_TokenCase>[
      _t('two words', 'Hello world', [('Hello', 0, 5), ('world', 6, 11)]),
      _t('contraction', "don't stop", [("don't", 0, 5), ('stop', 6, 10)]),
      _t('possessive', "James's book", [("James's", 0, 7), ('book', 8, 12)]),
      _t('curly contraction', 'don’t', [('don’t', 0, 5)]),
      _t('curly possessive', 'James’s', [('James’s', 0, 7)]),
      _t('modifier letter apostrophe', 'donʼt', [('donʼt', 0, 5)]),
      _t('plural possessive drops apostrophe', "dogs' bones", [
        ('dogs', 0, 4),
        ('bones', 6, 11),
      ]),
      _t('leading apostrophe dropped', "'tis", [('tis', 1, 4)]),
      _t('quotes around words', '"Hi," he said', [
        ('Hi', 1, 3),
        ('he', 6, 8),
        ('said', 9, 13),
      ]),
      _t('o clock', "o'clock", [("o'clock", 0, 7)]),
      _t('rock n roll with spaces', "rock 'n' roll", [
        ('rock', 0, 4),
        ('n', 6, 7),
        ('roll', 9, 13),
      ]),
      _t('rock-n-roll', "rock'n'roll", [("rock'n'roll", 0, 11)]),
      _t('hyphenated word', 'a well-known fact', [
        ('a', 0, 1),
        ('well-known', 2, 12),
        ('fact', 13, 17),
      ]),
      _t('long hyphenated', 'rock-and-roll', [('rock-and-roll', 0, 13)]),
      _t('double hyphen splits', 'yes--no', [('yes', 0, 3), ('no', 5, 7)]),
      _t('em dash splits', 'yes—no', [('yes', 0, 3), ('no', 4, 6)]),
      _t('hyphen before space splits', 'well- known', [
        ('well', 0, 4),
        ('known', 6, 11),
      ]),
      _t('hyphen with digits', 'a 3-year-old', [
        ('a', 0, 1),
        ('3-year-old', 2, 12),
      ]),
      _t('letters and digits', 'COVID-19 case', [
        ('COVID-19', 0, 8),
        ('case', 9, 13),
      ]),
      _t('pure numbers skipped', '1984 was 3.5', [('was', 5, 8)]),
      _t('ordinal kept', '3rd place', [('3rd', 0, 3), ('place', 4, 9)]),
      _t('e.g. gives two tokens', 'e.g. this', [
        ('e', 0, 1),
        ('g', 2, 3),
        ('this', 5, 9),
      ]),
      _t('Mr. drops period', 'Mr. Smith', [('Mr', 0, 2), ('Smith', 4, 9)]),
      _t('accented letters', 'café naïve', [('café', 0, 4), ('naïve', 5, 10)]),
      _t('emoji skipped, offsets in UTF-16', '\u{1F600} Hi', [('Hi', 3, 5)]),
      _t('trailing period', 'end.', [('end', 0, 3)]),
      _t('empty text', '', []),
      _t('punctuation only', '... -- !', []),
    ];
    for (final c in cases) {
      test(c.name, () {
        final actual = analyzer
            .tokens(c.text)
            .map((t) => (t.text, t.start, t.end))
            .toList();
        expect(actual, c.tokens);
        for (final (text, start, end) in c.tokens) {
          expect(c.text.substring(start, end), text);
        }
      });
    }
  });

  group('lemma', () {
    const cases = <(String, String)>[
      ('Running', 'running'),
      ('THE', 'the'),
      ('James’s', "james's"),
      ('DON’T', "don't"),
      ('ÉCOLE', 'école'),
      ('well-known', 'well-known'),
    ];
    for (final (word, expected) in cases) {
      test('$word -> $expected', () {
        expect(analyzer.lemma(word), expected);
      });
    }
  });
}
