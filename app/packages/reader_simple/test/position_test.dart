import 'package:core/domain_books.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_simple/src/position.dart';
import 'package:reader_simple/src/throttle.dart';

const _book = BookId('book-1');
const _chapter = ChapterRef(href: 'c0.xhtml', index: 0);

ContentDocument _doc(List<String> paragraphs) => ContentDocument([
  for (final p in paragraphs) ParagraphBlock([TextInline(p)]),
]);

Locator _locator({
  double progression = 0,
  TextQuote? quote,
  String? hint,
  ChapterRef chapter = _chapter,
}) => Locator(
  book: _book,
  chapter: chapter,
  progression: progression,
  quote: quote,
  engineHint: hint,
);

void main() {
  group('Throttle', () {
    test('runs at most once per interval, at exact times', () {
      fakeAsync((async) {
        final runs = <int>[];
        final throttle = Throttle(
          interval: const Duration(milliseconds: 500),
          action: () {
            runs.add(async.elapsed.inMilliseconds);
            return true;
          },
        );
        // A poke every 100 ms for 1.5 s.
        for (var t = 0; t < 1500; t += 100) {
          throttle.poke();
          async.elapse(const Duration(milliseconds: 100));
        }
        async.elapse(const Duration(seconds: 2));
        expect(runs, [0, 500, 1000, 1500]);
        throttle.dispose();
      });
    });

    test('the first poke runs at once, a lone poke runs once', () {
      fakeAsync((async) {
        var runs = 0;
        final throttle = Throttle(
          interval: const Duration(milliseconds: 500),
          action: () {
            runs++;
            return true;
          },
        )..poke();
        expect(runs, 1);
        async.elapse(const Duration(seconds: 5));
        expect(runs, 1);
        throttle.dispose();
      });
    });

    test('pokes inside the cooldown run once, when it ends', () {
      fakeAsync((async) {
        final runs = <int>[];
        final throttle = Throttle(
          interval: const Duration(milliseconds: 500),
          action: () {
            runs.add(async.elapsed.inMilliseconds);
            return true;
          },
        )..poke();
        async.elapse(const Duration(milliseconds: 100));
        throttle
          ..poke()
          ..poke()
          ..poke();
        async.elapse(const Duration(milliseconds: 399));
        expect(runs, [0]);
        async.elapse(const Duration(milliseconds: 1));
        expect(runs, [0, 500]);
        async.elapse(const Duration(seconds: 5));
        expect(runs, [0, 500]);
        throttle.dispose();
      });
    });

    test('an action that did nothing starts no cooldown', () {
      fakeAsync((async) {
        var runs = 0;
        Throttle(
            interval: const Duration(milliseconds: 500),
            action: () {
              runs++;
              return false;
            },
          )
          ..poke()
          ..poke()
          ..dispose();
        expect(runs, 2);
      });
    });

    test('dispose cancels the pending run', () {
      fakeAsync((async) {
        var runs = 0;
        Throttle(
            interval: const Duration(milliseconds: 500),
            action: () {
              runs++;
              return true;
            },
          )
          ..poke()
          ..poke()
          ..dispose();
        async.elapse(const Duration(seconds: 2));
        expect(runs, 1);
      });
    });
  });

  group('ChapterText', () {
    test('block text of compound blocks', () {
      expect(
        blockText(
          const QuoteBlock([
            ParagraphBlock([TextInline('a')]),
            ParagraphBlock([
              BoldInline([TextInline('b')]),
            ]),
          ]),
        ),
        'a\nb',
      );
      expect(
        blockText(
          const ListBlock(
            ordered: false,
            items: [
              [TextInline('x')],
              [TextInline('y')],
            ],
          ),
        ),
        'x\ny',
      );
      expect(blockText(const ImageBlock(src: 'i.png')), '');
    });

    test('progression of a position and back', () {
      final text = ChapterText.of(_doc(['aaaa', 'bbbbbbbb', 'cccc']));
      // "aaaa\nbbbbbbbb\ncccc" is 18 characters.
      expect(text.text.length, 18);
      expect(text.progressionOf(const BlockPosition(0, 0)), 0);
      expect(text.progressionOf(const BlockPosition(1, 0)), 5 / 18);
      expect(text.progressionOf(const BlockPosition(2, 2)), 16 / 18);
      for (final p in const [
        BlockPosition(0, 0),
        BlockPosition(0, 3),
        BlockPosition(1, 0),
        BlockPosition(1, 5),
        BlockPosition(2, 0),
        BlockPosition(2, 3),
      ]) {
        expect(text.fromProgression(text.progressionOf(p)), p);
      }
    });

    test('progression 1 is the start of the last block, 0 the start', () {
      final text = ChapterText.of(_doc(['aaaa', 'bbbb', 'cccc']));
      expect(text.fromProgression(1), const BlockPosition(2, 0));
      expect(text.fromProgression(0), const BlockPosition(0, 0));
    });

    test('empty chapter', () {
      final text = ChapterText.of(const ContentDocument([]));
      expect(text.fromProgression(0.5), const BlockPosition(0, 0));
      expect(text.find(const TextQuote(exact: 'x'), 0), isNull);
    });

    test('quote of the line at a position', () {
      final text = ChapterText.of(_doc(['one two three', 'four five six']));
      final quote = text.quoteAt(const BlockPosition(1, 5), lineEnd: 9);
      expect(
        quote,
        const TextQuote(
          exact: 'five',
          prefix: 'one two three four ',
          suffix: ' six',
        ),
      );
    });

    test('quote skips leading whitespace and is null over only whitespace', () {
      final text = ChapterText.of(_doc(['ab  cd', '  ']));
      expect(text.quoteAt(const BlockPosition(0, 2))?.exact, 'cd');
      expect(text.quoteAt(const BlockPosition(1, 0), lineEnd: 2), isNull);
    });

    test('find: the match whose surroundings agree wins', () {
      final text = ChapterText.of(
        _doc(['the cat sat', 'on the mat', 'the cat ran', 'to the mat']),
      );
      final second = text.find(
        const TextQuote(
          exact: 'the cat',
          prefix: 'on the mat ',
          suffix: ' ran',
        ),
        0,
      );
      expect(second, const BlockPosition(2, 0));
      final first = text.find(
        const TextQuote(exact: 'the cat', suffix: ' sat on'),
        1,
      );
      expect(first, const BlockPosition(0, 0));
    });

    test('find: whitespace runs do not matter', () {
      final text = ChapterText.of(_doc(['alpha\n  beta   gamma', 'delta']));
      expect(
        text.find(const TextQuote(exact: 'beta gamma delta'), 0),
        const BlockPosition(0, 8),
      );
    });

    test('find: equal scores go to the match nearest to progression', () {
      final text = ChapterText.of(_doc(['same', 'same', 'same']));
      const quote = TextQuote(exact: 'same');
      expect(text.find(quote, 0.9), const BlockPosition(2, 0));
      expect(text.find(quote, 0), const BlockPosition(0, 0));
    });

    test('find: several matches that all disagree are ambiguous', () {
      final text = ChapterText.of(_doc(['x one', 'x two']));
      expect(
        text.find(const TextQuote(exact: 'x', prefix: 'QQ', suffix: 'ZZ'), 0),
        isNull,
      );
    });

    test('find: absent text', () {
      final text = ChapterText.of(_doc(['alpha', 'beta']));
      expect(text.find(const TextQuote(exact: 'gamma'), 0), isNull);
    });
  });

  group('engineHint', () {
    final text = ChapterText.of(_doc(['aaaa', 'bbbb', 'cccc']));

    test('round trip', () {
      const at = BlockPosition(2, 3);
      expect(encodeHint(7, at), 'simple:1:7:2:3');
      expect(decodeHint(encodeHint(0, at), 0, text), at);
    });

    test('broken hints decode to null', () {
      for (final hint in [
        null,
        '',
        'garbage',
        'simple:1:0:1', // too short
        'simple:1:0:1:2:3', // too long
        'simple:2:0:1:2', // other version
        'other:1:0:1:2', // other engine
        'simple:1:x:1:2', // not numbers
        'simple:1:0:y:2',
        'simple:1:0:1:z',
        'simple:1:1:1:2', // other chapter
        'simple:1:0:3:0', // block out of range
        'simple:1:0:-1:0',
        'simple:1:0:1:5', // offset out of range
        'simple:1:0:1:-1',
      ]) {
        expect(decodeHint(hint, 0, text), isNull, reason: '$hint');
      }
    });
  });

  group('resolveLocator', () {
    final text = ChapterText.of(
      _doc([for (var i = 0; i < 10; i++) 'para $i alpha beta gamma delta']),
    );
    const quote = TextQuote(
      exact: 'gamma',
      prefix: 'para 7 alpha beta ',
      suffix: ' delta',
    );

    BlockPosition resolve(Locator l) =>
        resolveLocator(locator: l, chapter: 0, text: text);

    test('an intact hint wins over a different quote and progression', () {
      expect(
        resolve(_locator(progression: 0.9, hint: 'simple:1:0:3:2')),
        const BlockPosition(3, 2),
      );
    });

    test('a hint that agrees with the quote is used', () {
      // Offset 0 of block 7 starts with "para 7", the quote starts "gamma":
      // use the offset where "gamma" starts.
      expect(
        resolve(_locator(quote: quote, hint: 'simple:1:0:7:18')),
        const BlockPosition(7, 18),
      );
    });

    test('a hint that disagrees with the quote is dropped for the quote', () {
      expect(
        resolve(_locator(quote: quote, hint: 'simple:1:0:2:18')),
        const BlockPosition(7, 18),
      );
    });

    test('a broken hint falls back to the quote', () {
      for (final hint in ['garbage', 'simple:1:0:99:0', 'simple:1:5:7:18']) {
        expect(
          resolve(_locator(quote: quote, hint: hint)),
          const BlockPosition(7, 18),
          reason: hint,
        );
      }
    });

    test('a quote that is not in the chapter falls back to progression', () {
      expect(
        resolve(
          _locator(
            progression: 0.5,
            quote: const TextQuote(exact: 'not in the text'),
            hint: 'garbage',
          ),
        ),
        text.fromProgression(0.5),
      );
    });

    test('without hint and quote the progression decides', () {
      expect(resolve(_locator(progression: 1)), const BlockPosition(9, 0));
      expect(resolve(_locator()), const BlockPosition(0, 0));
      expect(resolve(_locator(progression: 0.5)).block, inInclusiveRange(4, 5));
    });
  });
}
