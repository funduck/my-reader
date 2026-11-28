import 'package:core/application.dart';
import 'package:core/domain_lookup.dart';
import 'package:test/test.dart';

CheatSheetItem _item(
  String text,
  CefrLevel level, [
  double? zipf,
  int lookups = 0,
  bool name = false,
]) => CheatSheetItem(
  text: text,
  kind: CheatSheetItemKind.word,
  level: level,
  zipf: zipf,
  lookupCount: lookups,
  isProperName: name,
);

List<String> _texts(List<CheatSheetItem> items) => [
  for (final i in items) i.text,
];

void main() {
  group('selectCheatSheetItems', () {
    final items = [
      _item('a', CefrLevel.c1, 3),
      _item('b', CefrLevel.b2, 4),
      _item('c', CefrLevel.b1, 5),
      _item('d', CefrLevel.c2, 2),
      _item('e', CefrLevel.unknown, 6),
      _item('f', CefrLevel.c1),
      _item('g', CefrLevel.c1, 3),
    ];

    test('keeps only levels strictly above, sorted by Zipf descending', () {
      final picked = selectCheatSheetItems(
        items,
        above: CefrLevel.b1,
        limit: null,
      );
      expect(_texts(picked), ['b', 'a', 'g', 'd', 'f']);
    });

    test('equal Zipf keeps the generator order', () {
      final picked = selectCheatSheetItems(
        items,
        above: CefrLevel.a1,
        limit: null,
      );
      expect(
        _texts(picked).indexOf('a'),
        lessThan(_texts(picked).indexOf('g')),
      );
    });

    test('items without Zipf go last, in the generator order', () {
      final picked = selectCheatSheetItems(
        [
          _item('x', CefrLevel.c1),
          _item('y', CefrLevel.c1, 1),
          _item('z', CefrLevel.c1),
        ],
        above: CefrLevel.b2,
        limit: null,
      );
      expect(_texts(picked), ['y', 'x', 'z']);
    });

    test('limit takes the first items after sorting', () {
      final picked = selectCheatSheetItems(
        items,
        above: CefrLevel.b1,
        limit: 2,
      );
      expect(_texts(picked), ['b', 'a']);
    });

    test('limit larger than the list and null give everything', () {
      final all = selectCheatSheetItems(items, above: CefrLevel.b1, limit: 50);
      expect(all, hasLength(5));
      expect(
        selectCheatSheetItems(items, above: CefrLevel.b1, limit: null),
        all,
      );
    });

    test('hidden words are dropped before the limit', () {
      final picked = selectCheatSheetItems(
        items,
        above: CefrLevel.b1,
        limit: 2,
        hidden: {'b'},
      );
      expect(_texts(picked), ['a', 'g']);
    });

    test('unknown level is never above', () {
      final picked = selectCheatSheetItems(
        items,
        above: CefrLevel.a1,
        limit: null,
      );
      expect(_texts(picked), isNot(contains('e')));
    });

    test('does not change the input', () {
      final copy = [...items];
      selectCheatSheetItems(items, above: CefrLevel.a1, limit: 1);
      expect(items, copy);
    });

    test('minBars drops rare words and words without Zipf', () {
      List<String> pick(int minBars) => _texts(
        selectCheatSheetItems(
          items,
          above: CefrLevel.a1,
          limit: null,
          minBars: minBars,
        ),
      );
      // Bars: a 3, b 4, c 5, d 2, f none, g 3.
      expect(pick(3), ['c', 'b', 'a', 'g']);
      expect(pick(4), ['c', 'b']);
      expect(pick(5), ['c']);
      expect(pick(2), ['c', 'b', 'a', 'g', 'd']);
    });

    test('minBars: 1 gives the same result as no threshold', () {
      final one = [1].first; // not a literal: 1 is the default
      expect(
        selectCheatSheetItems(
          items,
          above: CefrLevel.b1,
          limit: null,
          minBars: one,
        ),
        selectCheatSheetItems(items, above: CefrLevel.b1, limit: null),
      );
      expect(
        _texts(
          selectCheatSheetItems(
            items,
            above: CefrLevel.b1,
            limit: null,
            minBars: one,
          ),
        ),
        ['b', 'a', 'g', 'd', 'f'],
      );
    });

    test('minBars applies before the limit', () {
      final picked = selectCheatSheetItems(
        items,
        above: CefrLevel.a1,
        limit: 3,
        minBars: 3,
      );
      expect(_texts(picked), ['c', 'b', 'a']);
    });
  });

  group('isDifficult', () {
    test('level above, not hidden, enough bars', () {
      final item = _item('x', CefrLevel.c1, 4.5);
      expect(isDifficult(item, above: CefrLevel.b2), isTrue);
      expect(isDifficult(item, above: CefrLevel.c1), isFalse);
      expect(isDifficult(item, above: CefrLevel.b2, hidden: {'x'}), isFalse);
      expect(isDifficult(item, above: CefrLevel.b2, minBars: 4), isTrue);
      expect(isDifficult(item, above: CefrLevel.b2, minBars: 5), isFalse);
    });

    test('without Zipf only passes minBars 1; unknown level never', () {
      final noZipf = _item('x', CefrLevel.c1);
      expect(isDifficult(noZipf, above: CefrLevel.b2), isTrue);
      expect(isDifficult(noZipf, above: CefrLevel.b2, minBars: 2), isFalse);
      expect(
        isDifficult(_item('y', CefrLevel.unknown, 5), above: CefrLevel.a1),
        isFalse,
      );
    });

    test('matches selectCheatSheetItems without a limit', () {
      final items = [
        _item('a', CefrLevel.c1, 3),
        _item('b', CefrLevel.b2, 4),
        _item('c', CefrLevel.c2),
        _item('d', CefrLevel.a2, 5),
      ];
      for (var bars = 1; bars <= 5; bars++) {
        final picked = selectCheatSheetItems(
          items,
          above: CefrLevel.b1,
          limit: null,
          hidden: {'b'},
          minBars: bars,
        );
        final difficult = [
          for (final i in items)
            if (isDifficult(
              i,
              above: CefrLevel.b1,
              minBars: bars,
              hidden: {'b'},
            ))
              i,
        ];
        expect(_texts(difficult), unorderedEquals(_texts(picked)));
      }
    });
  });

  group('zipfBars', () {
    test('null without Zipf', () => expect(zipfBars(null), isNull));

    test('thresholds', () {
      expect(zipfBars(7), 5);
      expect(zipfBars(5), 5);
      expect(zipfBars(4.99), 4);
      expect(zipfBars(4), 4);
      expect(zipfBars(3.99), 3);
      expect(zipfBars(3), 3);
      expect(zipfBars(2.99), 2);
      expect(zipfBars(2), 2);
      expect(zipfBars(1.99), 1);
      expect(zipfBars(0), 1);
      expect(zipfBars(-1), 1);
    });
  });

  group('shortQuote', () {
    const long =
        'one two three four five six seven eight nine ten eleven twelve '
        'thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty.';

    test('word at the start cuts only the right side', () {
      expect(
        shortQuote(long, 'one'),
        'one two three four five six seven eight …',
      );
    });

    test('word in the middle cuts both sides', () {
      expect(
        shortQuote(long, 'ten'),
        '… three four five six seven eight nine ten eleven twelve thirteen '
        'fourteen fifteen sixteen seventeen …',
      );
    });

    test('word at the end cuts only the left side', () {
      expect(
        shortQuote(long, 'twenty'),
        '… thirteen fourteen fifteen sixteen seventeen eighteen nineteen '
        'twenty.',
      );
    });

    test('punctuation next to the word stays and does not block the match', () {
      expect(
        shortQuote('He said, "Hello," and left.', 'hello'),
        'He said, "Hello," and left.',
      );
      expect(
        shortQuote('$long Then "end".', 'end'),
        '… fifteen sixteen seventeen eighteen nineteen twenty. Then "end".',
      );
    });

    test('the first occurrence wins', () {
      expect(
        shortQuote('a b c d e f g h i j run k l m n o p q r s t run', 'run'),
        '… d e f g h i j run k l m n o p q …',
      );
    });

    test('whole words only, case-insensitive', () {
      expect(
        shortQuote('Running runs. RUN now.', 'run'),
        'Running runs. RUN now.',
      );
      expect(
        shortQuote(
          'Running is fun, so go and RUN far away from here today '
              'and tomorrow and later',
          'run',
        ),
        'Running is fun, so go and RUN far away from here today and tomorrow '
        '…',
      );
    });

    test('word not found gives the whole sentence', () {
      expect(shortQuote(long, 'missing'), long);
    });

    test('short sentence has no ellipsis', () {
      expect(shortQuote('A short one.', 'short'), 'A short one.');
    });

    test('window is configurable', () {
      expect(shortQuote('a b c d e', 'c', window: 1), '… b c d …');
      expect(shortQuote('a b c d e', 'c', window: 2), 'a b c d e');
    });
  });

  group('looked-up words (T-121)', () {
    final items = [
      _item('above', CefrLevel.c1, 4),
      _item('below', CefrLevel.a1, 6, 2),
      _item('rare', CefrLevel.a2, 1, 1),
      _item('nolevel', CefrLevel.unknown, null, 3),
      _item('london', CefrLevel.c1, 3, 1, true),
      _item('plain', CefrLevel.a1, 6),
      _item('name', CefrLevel.c1, 5, 0, true),
      _item('seen', CefrLevel.c2, 2, 4),
    ];

    List<String> pick({
      int? limit,
      int minBars = 1,
      Set<String> hidden = const {},
    }) => _texts(
      selectCheatSheetItems(
        items,
        above: CefrLevel.b2,
        limit: limit,
        minBars: minBars,
        hidden: hidden,
      ),
    );

    test('a looked-up word is picked below the level, below the threshold, '
        'with an unknown level and as a proper name', () {
      // Frequent first: below 6, above 4, london 3, seen 2, rare 1, no zipf.
      expect(pick(), ['below', 'above', 'london', 'seen', 'rare', 'nolevel']);
      expect(pick(minBars: 5), ['below', 'london', 'seen', 'rare', 'nolevel']);
    });

    test('a word that was not looked up still needs level and threshold', () {
      final names = pick(minBars: 3);
      expect(names, isNot(contains('plain')));
      expect(names, isNot(contains('name')));
    });

    test('a word marked known is never picked', () {
      expect(pick(hidden: {'below', 'nolevel', 'above'}), [
        'london',
        'seen',
        'rare',
      ]);
    });

    test('the limit cuts the joint list by frequency, no quota', () {
      expect(pick(limit: 3), ['below', 'above', 'london']);
      expect(pick(limit: 1), ['below']);
    });

    test('an expression is not made difficult by lookups', () {
      const phrase = CheatSheetItem(
        text: 'give up',
        kind: CheatSheetItemKind.expression,
        level: CefrLevel.a1,
        lookupCount: 5,
      );
      expect(isDifficult(phrase, above: CefrLevel.b2), isFalse);
    });

    test('isDifficult: the proper-name flag only blocks the level rule', () {
      expect(
        isDifficult(_item('x', CefrLevel.c2, 3, 0, true), above: CefrLevel.a1),
        isFalse,
      );
      expect(
        isDifficult(_item('x', CefrLevel.c2, 3, 1, true), above: CefrLevel.a1),
        isTrue,
      );
    });
  });
}
