import 'dart:typed_data';

import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:test/test.dart';

/// Words by regex, sentences up to `.`, `!` or `?`; the lemma is the word in
/// lower case.
class _Analyzer implements TextAnalyzer {
  const new();

  @override
  List<SentenceSpan> sentences(String text) => [
    for (final m in RegExp('[^.!?]+[.!?]*').allMatches(text))
      if (m.group(0)!.trim().isNotEmpty) SentenceSpan(m.start, m.end),
  ];

  @override
  List<TextToken> tokens(String text) => [
    for (final m in RegExp("[A-Za-z]+(?:'[A-Za-z]+)?").allMatches(text))
      TextToken(m.group(0)!, m.start, m.end),
  ];

  @override
  String lemma(String word) => word.toLowerCase();
}

class _Levels implements LevelDictionary {
  const new(this.table);

  final Map<String, WordLevel> table;

  @override
  WordLevel levelOf(String lemma, {String? pos}) =>
      table[lemma] ?? const WordLevel(CefrLevel.unknown);
}

class _Book implements OpenedBook {
  const new(this.chapters);

  final List<String> chapters;

  @override
  List<ChapterRef> get spine => [
    for (var i = 0; i < chapters.length; i++)
      ChapterRef(href: 'c$i.xhtml', index: i),
  ];

  @override
  List<TocEntry> get toc => const [];

  @override
  Future<ContentDocument> chapter(ChapterRef ref) async => ContentDocument([
    ParagraphBlock([TextInline(chapters[ref.index])]),
  ]);

  @override
  Future<Uint8List> resource(String href) => throw UnimplementedError();

  @override
  Future<void> close() async {}
}

class _RecordingGenerator implements CheatSheetGenerator {
  new(this.inner);

  final CheatSheetGenerator inner;
  final List<({String text, Set<String> known})> calls = [];

  @override
  Future<CheatSheet> generate({
    required String text,
    required Locator from,
    required Locator to,
    Set<String> knownTerms = const {},
    CancelToken? cancel,
  }) {
    calls.add((text: text, known: knownTerms));
    return inner.generate(
      text: text,
      from: from,
      to: to,
      knownTerms: knownTerms,
      cancel: cancel,
    );
  }
}

WordLevel _w(CefrLevel level, [double? zipf]) => WordLevel(level, zipf: zipf);

const _bookId = BookId('b');

ChapterRef _ref(int i) => ChapterRef(href: 'c$i.xhtml', index: i);

void main() {
  late _RecordingGenerator generator;
  late ChapterDifficultWords words;

  void setUpLevels(Map<String, WordLevel> table) {
    generator = _RecordingGenerator(
      LevelCheatSheetGenerator(
        analyzer: const _Analyzer(),
        levels: _Levels(table),
      ),
    );
    words = ChapterDifficultWords(generator: generator);
  }

  group('ChapterDifficultWords', () {
    test('takes the words strictly above the level of the reader', () async {
      setUpLevels({
        'apple': _w(CefrLevel.a2),
        'bridge': _w(CefrLevel.b1),
        'cargo': _w(CefrLevel.b2),
        'dusk': _w(CefrLevel.c1),
        'ember': _w(CefrLevel.c2),
        'mystery': const WordLevel(CefrLevel.unknown),
      });
      const book = _Book(['Apple bridge cargo dusk ember mystery.']);

      expect(await words(book, _bookId, _ref(0), level: CefrLevel.b1), {
        'cargo',
        'dusk',
        'ember',
      });
      expect(await words(book, _bookId, _ref(0), level: CefrLevel.b2), {
        'dusk',
        'ember',
      });
      expect(await words(book, _bookId, _ref(0), level: CefrLevel.c2), isEmpty);
    });

    test('the threshold keeps the words with enough frequency bars', () async {
      // Bars: 5 from 5.0, 4 from 4.0, 3 from 3.0, 2 from 2.0, otherwise 1.
      setUpLevels({
        'five': _w(CefrLevel.c1, 6),
        'four': _w(CefrLevel.c1, 4.5),
        'three': _w(CefrLevel.c1, 3.5),
        'two': _w(CefrLevel.c1, 2.5),
        'one': _w(CefrLevel.c1, 1),
        'none': _w(CefrLevel.c1),
      });
      const book = _Book(['Five four three two one none.']);

      Future<Set<String>> run(int bars) =>
          words(book, _bookId, _ref(0), level: CefrLevel.b2, minBars: bars);

      expect(await run(1), {'five', 'four', 'three', 'two', 'one', 'none'});
      expect(await run(2), {'five', 'four', 'three', 'two'});
      expect(await run(3), {'five', 'four', 'three'});
      expect(await run(4), {'five', 'four'});
      expect(await run(5), {'five'});
    });

    test('words marked known are left out', () async {
      setUpLevels({
        'alpha': _w(CefrLevel.c1),
        'beta': _w(CefrLevel.c1),
        'gamma': _w(CefrLevel.c2),
      });
      const book = _Book(['Alpha beta gamma.']);

      expect(
        await words(
          book,
          _bookId,
          _ref(0),
          level: CefrLevel.b2,
          known: {'beta'},
        ),
        {'alpha', 'gamma'},
      );
    });

    test('the three rules work together', () async {
      setUpLevels({
        'easy': _w(CefrLevel.a1, 6),
        'rare': _w(CefrLevel.c1, 1),
        'known': _w(CefrLevel.c1, 5),
        'hit': _w(CefrLevel.c2, 5),
        'hard': _w(CefrLevel.c1, 3.5),
      });
      const book = _Book(['Easy rare known hit hard.']);

      expect(
        await words(
          book,
          _bookId,
          _ref(0),
          level: CefrLevel.b2,
          minBars: 3,
          known: {'known'},
        ),
        {'hit', 'hard'},
      );
    });

    test(
      'only the text of the chapter is read, and no terms are given',
      () async {
        setUpLevels({
          'alpha': _w(CefrLevel.c1),
          'beta': _w(CefrLevel.c1),
          'gamma': _w(CefrLevel.c1),
        });
        const book = _Book(['Alpha. Alpha again.', 'Beta.', 'Gamma.']);

        expect(await words(book, _bookId, _ref(1), level: CefrLevel.b2), {
          'beta',
        });
        expect(generator.calls.single.text, 'Beta.');
        expect(generator.calls.single.known, isEmpty);
      },
    );

    test('a chapter outside the book gives no words', () async {
      setUpLevels({'alpha': _w(CefrLevel.c1)});
      const book = _Book(['Alpha.']);

      expect(await words(book, _bookId, _ref(5), level: CefrLevel.b2), isEmpty);
      expect(generator.calls, isEmpty);
    });

    test('pick works over the candidates without the generator', () async {
      setUpLevels({'alpha': _w(CefrLevel.c1, 5), 'beta': _w(CefrLevel.c2, 2)});
      const book = _Book(['Alpha beta.']);
      final candidates = await words.candidates(book, _bookId, _ref(0));

      expect(candidates.map((i) => i.text), {'alpha', 'beta'});
      expect(words.pick(candidates, level: CefrLevel.b2), {'alpha', 'beta'});
      expect(words.pick(candidates, level: CefrLevel.c1), {'beta'});
      expect(words.pick(candidates, level: CefrLevel.b2, minBars: 3), {
        'alpha',
      });
      expect(words.pick(candidates, level: CefrLevel.b2, known: {'beta'}), {
        'alpha',
      });
      expect(generator.calls, hasLength(1));
    });

    test('a cancelled token stops the work', () async {
      setUpLevels({'alpha': _w(CefrLevel.c1)});
      final cancel = CancelToken()..cancel();

      await expectLater(
        words(
          const _Book(['Alpha.']),
          _bookId,
          _ref(0),
          level: CefrLevel.b2,
          cancel: cancel,
        ),
        throwsA(isA<CancelledException>()),
      );
    });

    test('a chapter of 15 000 words is done in under a second', () async {
      final levels = <String, WordLevel>{};
      final buffer = StringBuffer();
      for (var i = 0; i < 15000; i++) {
        final word = 'w${_letters(i % 3000)}';
        levels[word] = _w(CefrLevel.values[1 + i % 5], 1 + (i % 50) / 10);
        buffer
          ..write(word)
          ..write(i % 12 == 11 ? '. ' : ' ');
      }
      setUpLevels(levels);
      final book = _Book([buffer.toString()]);

      final watch = Stopwatch()..start();
      final result = await words(book, _bookId, _ref(0), level: CefrLevel.b1);
      watch.stop();

      expect(result, isNotEmpty);
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });
  });
}

/// A letters-only name for [n]: the fake analyzer reads only letters.
String _letters(int n) {
  final buffer = StringBuffer();
  var rest = n;
  do {
    buffer.writeCharCode(0x61 + rest % 26);
    rest ~/= 26;
  } while (rest > 0);
  return buffer.toString();
}
