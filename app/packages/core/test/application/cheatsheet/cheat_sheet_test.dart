import 'dart:typed_data';

import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:test/test.dart';

/// Words by regex, sentences up to `.`, `!` or `?`; lemma is a table lookup
/// over the lower-cased word.
class _Analyzer implements TextAnalyzer {
  const new([this.lemmas = const {}]);

  final Map<String, String> lemmas;

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
  String lemma(String word) {
    final lower = word.toLowerCase();
    return lemmas[lower] ?? lower;
  }
}

class _Levels implements LevelDictionary {
  const new(this.table);

  final Map<String, WordLevel> table;

  @override
  WordLevel levelOf(String lemma, {String? pos}) =>
      table[lemma] ?? const WordLevel(CefrLevel.unknown);
}

WordLevel _w(CefrLevel level, [double? zipf]) => WordLevel(level, zipf: zipf);

const _bookId = BookId('b');
const _ch0 = ChapterRef(href: 'c0.xhtml', index: 0);
const _from = Locator(book: _bookId, chapter: _ch0, progression: 0);
const _to = Locator(book: _bookId, chapter: _ch0, progression: 1);

Future<List<CheatSheetItem>> _run(
  String text,
  Map<String, WordLevel> levels, {
  Set<String> known = const {},
  Map<String, String> lemmas = const {},
}) async {
  final sheet = await LevelCheatSheetGenerator(
    analyzer: _Analyzer(lemmas),
    levels: _Levels(levels),
  ).generate(text: text, from: _from, to: _to, knownTerms: known);
  return sheet.items;
}

class _Profiles implements ProfileRepository {
  new(this.profile);

  UserProfile profile;

  @override
  Future<UserProfile> get() async => profile;

  @override
  Stream<UserProfile> watch() => Stream.value(profile);

  @override
  Future<void> save(UserProfile profile) async => this.profile = profile;

  @override
  Future<UserProfile> update(UserProfile Function(UserProfile) change) async {
    final next = change(await get());
    await save(next);
    return next;
  }
}

class _Terms implements TermRepository {
  const new(this.terms);

  final List<Term> terms;

  @override
  Future<Term?> find(String normalized, String language) async => null;

  @override
  Stream<List<Term>> watchAll({TermStatus? status}) => Stream.value([
    for (final t in terms)
      if (status == null || t.status == status) t,
  ]);

  @override
  Future<void> save(Term term) async {}
}

Term _term(
  String normalized, {
  String language = 'en',
  TermStatus status = TermStatus.learning,
  int lookups = 1,
}) => Term(
  id: TermId('t-$language-$normalized'),
  normalized: normalized,
  language: language,
  lookupCount: lookups,
  eventIds: const [],
  status: status,
);

class _Book implements OpenedBook {
  const new(this.paragraphs);

  final List<String> paragraphs;

  @override
  List<ChapterRef> get spine => const [_ch0];

  @override
  List<TocEntry> get toc => const [];

  @override
  Future<ContentDocument> chapter(ChapterRef ref) async => ContentDocument([
    for (final p in paragraphs) ParagraphBlock([TextInline(p)]),
  ]);

  @override
  Future<Uint8List> resource(String href) => throw UnimplementedError();

  @override
  Future<void> close() async {}
}

class _RecordingGenerator implements CheatSheetGenerator {
  String? text;
  Locator? from;
  Locator? to;
  Set<String>? knownTerms;

  @override
  Future<CheatSheet> generate({
    required String text,
    required Locator from,
    required Locator to,
    Set<String> knownTerms = const {},
    CancelToken? cancel,
  }) async {
    this.text = text;
    this.from = from;
    this.to = to;
    this.knownTerms = knownTerms;
    return CheatSheet(from: from, to: to, items: const []);
  }
}

void main() {
  group('LevelCheatSheetGenerator', () {
    test('keeps every word, hardest first', () async {
      final items = await _run('cat ephemeral sun ubiquitous window arcane', {
        'cat': _w(CefrLevel.a1),
        'sun': _w(CefrLevel.b1),
        'window': _w(CefrLevel.b2),
        'ephemeral': _w(CefrLevel.c2),
        'ubiquitous': _w(CefrLevel.c1),
        'arcane': _w(CefrLevel.c1),
      });
      expect(items.map((i) => i.text), [
        'ephemeral',
        'ubiquitous',
        'arcane',
        'window',
        'sun',
        'cat',
      ]);
      expect(items.first.level, CefrLevel.c2);
      expect(items.first.kind, CheatSheetItemKind.word);
    });

    test('keeps words with an unknown level, after the known ones', () async {
      final items = await _run('mystery hard', {'hard': _w(CefrLevel.c1)});
      expect(items.map((i) => i.text), ['hard', 'mystery']);
      expect(items.last.level, CefrLevel.unknown);
    });

    test('levels are looked up by lemma and forms are merged', () async {
      final items = await _run(
        'He ran. They run. Running is fun.',
        {'run': _w(CefrLevel.c1)},
        lemmas: {'ran': 'run', 'running': 'run'},
      );
      expect(items.firstWhere((i) => i.text == 'run').level, CefrLevel.c1);
      expect(items.where((i) => i.text == 'run'), hasLength(1));
    });

    test('drops words from knownTerms', () async {
      final levels = {'alpha': _w(CefrLevel.c1), 'beta': _w(CefrLevel.c1)};
      final items = await _run('alpha beta', levels, known: {'alpha'});
      expect(items.map((i) => i.text), ['beta']);
    });

    test(
      'flags proper names: capital not at the start of a sentence',
      () async {
        final levels = {
          'london': _w(CefrLevel.c1),
          'brown': _w(CefrLevel.c1),
          'quixotic': _w(CefrLevel.c1),
          'tuesday': _w(CefrLevel.c1),
          'arcade': _w(CefrLevel.c1),
        };
        final items = await _run(
          'He went to London. London was big. "Quixotic," said Mr Brown. '
          'The brown dog barked. Tuesday came. A quixotic arcade.',
          levels,
        );
        // london: only capitalized, once mid-sentence: name.
        // brown: also lower case: common word.
        // quixotic: first occurrence at the start of a quote is not a name
        //   anyway, and it appears in lower case.
        // tuesday: only at the start of a sentence: not proven a name.
        final names = {
          for (final i in items)
            if (i.isProperName) i.text,
        };
        expect(names, {'london', 'mr'});
        expect(items.map((i) => i.text), contains('london'));
      },
    );

    test('a sentence starting with a quote still counts its first word as '
        'the start', () async {
      final items = await _run('He left. "Zephyr" blew.', {
        'zephyr': _w(CefrLevel.c1),
      });
      expect(items.firstWhere((i) => i.text == 'zephyr').isProperName, isFalse);
    });

    test('ranks by level, then lower Zipf, then count, then first '
        'occurrence', () async {
      final levels = {
        'a': _w(CefrLevel.c2, 2),
        'b': _w(CefrLevel.c1, 3),
        'c': _w(CefrLevel.c1, 2),
        'd': _w(CefrLevel.c1, 3),
        'e': _w(CefrLevel.c1, 3),
        'f': _w(CefrLevel.c1),
      };
      // d occurs twice, b and e once; b comes before e.
      final items = await _run('b e d d f c a', levels);
      expect(items.map((i) => i.text), ['a', 'f', 'c', 'd', 'b', 'e']);
    });

    test('does not cut the list by count', () async {
      final names = [for (var i = 0; i < 60; i++) 'x${'a' * i}'];
      final levels = {
        for (var i = 0; i < names.length; i++)
          names[i]: _w(CefrLevel.c1, 1.0 + i / 100),
      };
      final items = await _run(names.reversed.join(' '), levels);
      expect(items.map((i) => i.text), names);
    });

    test('items carry the Zipf frequency', () async {
      final items = await _run('alpha beta', {
        'alpha': _w(CefrLevel.c1, 3.5),
        'beta': _w(CefrLevel.c1),
      });
      expect(items.map((i) => i.zipf), [null, 3.5]);
    });

    test('example is the first sentence of the text with the word', () async {
      final items = await _run(
        'Nothing here.  An\nephemeral thing. Another ephemeral one.',
        {'ephemeral': _w(CefrLevel.c1)},
      );
      final item = items.firstWhere((i) => i.text == 'ephemeral');
      expect(item.example, 'An ephemeral thing.');
      expect(item.translation, isNull);
    });

    test(
      'example is a short quote around the word form, not the lemma',
      () async {
        final items = await _run(
          'One two three four five six seven eight ran nine ten eleven twelve '
          'thirteen fourteen fifteen sixteen.',
          {'run': _w(CefrLevel.c1)},
          lemmas: {'ran': 'run'},
        );
        expect(
          items.firstWhere((i) => i.text == 'run').example,
          '… two three four five six seven eight ran nine ten eleven twelve '
          'thirteen fourteen fifteen …',
        );
      },
    );

    test('result carries from and to; empty text gives no items', () async {
      final sheet = await const LevelCheatSheetGenerator(
        analyzer: _Analyzer(),
        levels: _Levels({}),
      ).generate(text: '', from: _from, to: _to);
      expect(sheet.items, isEmpty);
      expect(sheet.from, _from);
      expect(sheet.to, _to);
    });

    test('cancelled token throws', () async {
      final cancel = CancelToken()..cancel();
      expect(
        const LevelCheatSheetGenerator(
          analyzer: _Analyzer(),
          levels: _Levels({}),
        ).generate(text: 'x', from: _from, to: _to, cancel: cancel),
        throwsA(isA<CancelledException>()),
      );
    });
  });

  group('BuildCheatSheet', () {
    test('passes the piece and the known lemmas to the '
        'generator', () async {
      final generator = _RecordingGenerator();
      final build = BuildCheatSheet(
        generator: generator,
        profiles: _Profiles(
          const UserProfile(level: CefrLevel.c1, scope: CheatSheetChapter()),
        ),
        terms: _Terms([
          _term('alpha', status: TermStatus.known),
          _term('beta'),
          _term('gamma', language: 'ru', status: TermStatus.known),
        ]),
      );
      final sheet = await build(
        const _Book(['First one.', 'Second one.']),
        from: _from,
      );
      expect(sheet, isNotNull);
      expect(generator.text, 'First one.\n\nSecond one.');
      expect(generator.knownTerms, {'alpha'});
      expect(generator.from!.chapter, _ch0);
      expect(generator.from!.progression, 0);
      expect(generator.to!.progression, 1);
    });

    test('uses the scope of the profile', () async {
      final generator = _RecordingGenerator();
      final build = BuildCheatSheet(
        generator: generator,
        profiles: _Profiles(const UserProfile(scope: CheatSheetPages(1))),
        terms: const _Terms([]),
      );
      // Two paragraphs of 200 words: one page (300) is reached by the second.
      final p = List.filled(200, 'word').join(' ');
      await build(_Book([p, p, p]), from: _from);
      expect(generator.text, '$p\n\n$p');
    });

    test('returns null when the position is not in the book', () async {
      final generator = _RecordingGenerator();
      final build = BuildCheatSheet(
        generator: generator,
        profiles: _Profiles(const UserProfile()),
        terms: const _Terms([]),
      );
      const other = Locator(
        book: _bookId,
        chapter: ChapterRef(href: 'zz.xhtml', index: 9),
        progression: 0,
      );
      expect(await build(const _Book(['Text.']), from: other), isNull);
      expect(generator.text, isNull);
    });

    test('end to end: looked-up words stay, known ones go', () async {
      final build = BuildCheatSheet(
        generator: LevelCheatSheetGenerator(
          analyzer: const _Analyzer(),
          levels: _Levels({
            'ephemeral': _w(CefrLevel.c2, 2),
            'ubiquitous': _w(CefrLevel.c1, 3),
            'arcane': _w(CefrLevel.c1, 2),
            'london': _w(CefrLevel.c1, 3),
            'cat': _w(CefrLevel.a1, 6),
          }),
        ),
        profiles: _Profiles(const UserProfile()),
        terms: _Terms([
          _term('arcane', lookups: 3),
          _term('ubiquitous', status: TermStatus.known),
          _term('london', lookups: 2),
          _term('mystery'),
          _term('ephemeral', lookups: 0),
        ]),
      );
      final sheet = await build(
        const _Book([
          'The cat saw London. Ephemeral, ubiquitous arcane magic. A mystery.',
        ]),
        from: _from,
      );
      final counts = {for (final i in sheet!.items) i.text: i.lookupCount};
      // ubiquitous is known: gone. arcane, london (a proper name) and
      // mystery (no level) were looked up: kept with their counts.
      expect(counts, {
        'ephemeral': 0,
        'arcane': 3,
        'london': 2,
        'mystery': 1,
        'the': 0,
        'saw': 0,
        'magic': 0,
        'a': 0,
        'cat': 0,
      });
      final london = sheet.items.firstWhere((i) => i.text == 'london');
      expect(london.isProperName, isTrue);
      final mystery = sheet.items.firstWhere((i) => i.text == 'mystery');
      expect(mystery.level, CefrLevel.unknown);
    });
  });
}
