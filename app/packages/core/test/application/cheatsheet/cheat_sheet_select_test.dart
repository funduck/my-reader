import 'package:core/application.dart';
import 'package:core/domain_lookup.dart';
import 'package:test/test.dart';

CheatSheetItem _item(String text, CefrLevel level, [double? zipf]) =>
    CheatSheetItem(
      text: text,
      kind: CheatSheetItemKind.word,
      level: level,
      zipf: zipf,
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
}
