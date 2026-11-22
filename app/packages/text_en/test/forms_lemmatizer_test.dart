import 'dart:io';

import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:test/test.dart';
import 'package:text_en/text_en.dart';

const _pack = '../../../service/fixtures/packs/en-forms-20260101.1.sqlite';

void main() {
  late FormsLemmatizer lemmatizer;

  setUp(() => lemmatizer = FormsLemmatizer.open(_pack));
  tearDown(() => lemmatizer.close());

  test('fixture exists', () => expect(File(_pack).existsSync(), isTrue));

  group('form to lemma', () {
    const cases = [
      ('running', 'run'),
      ('went', 'go'),
      ('mice', 'mouse'),
      ('children', 'child'),
      ('happiest', 'happy'),
    ];
    for (final (form, lemma) in cases) {
      test('$form -> $lemma', () => expect(lemmatizer.lemma(form), lemma));
    }

    test('case and whitespace are normalized', () {
      expect(lemmatizer.lemma('RUNNING'), 'run');
      expect(lemmatizer.lemma('  Went '), 'go');
    });
  });

  group('several candidates', () {
    test('lowest rank wins', () {
      expect(lemmatizer.lemma('better'), 'good');
      expect(lemmatizer.lemma('left'), 'leave');
      expect(lemmatizer.lemma('runs'), 'run');
    });

    test('pos filter picks a lower-ranked candidate', () {
      expect(lemmatizer.lemma('better', pos: 'adv'), 'well');
      expect(lemmatizer.lemma('left', pos: 'adj'), 'left');
      expect(lemmatizer.lemma('runs', pos: 'noun'), 'run');
    });

    test('pos without a match returns the form itself', () {
      expect(lemmatizer.lemma('went', pos: 'noun'), 'went');
    });
  });

  group('unknown and odd tokens', () {
    test('unknown word is returned itself, normalized', () {
      expect(lemmatizer.lemma('Zyzzyva'), 'zyzzyva');
      expect(lemmatizer.lemma('Wa’it'), "wa'it");
    });

    test('empty and blank input', () {
      expect(lemmatizer.lemma(''), '');
      expect(lemmatizer.lemma('   '), '');
    });

    test('whole hyphenated form in the table is found', () {
      expect(lemmatizer.lemma('mothers-in-law'), 'mother-in-law');
    });

    test('hyphenated token: last part is lemmatized if known', () {
      expect(lemmatizer.lemma('well-known'), 'well-known');
      expect(lemmatizer.lemma('ex-running'), 'ex-run');
      expect(lemmatizer.lemma('Ex-Going'), 'ex-go');
    });

    test('possessive suffix is stripped when the stem is known', () {
      expect(lemmatizer.lemma("dogs's"), 'dog');
      expect(lemmatizer.lemma('dogs’s'), 'dog');
      expect(lemmatizer.lemma("James's"), "james's");
    });

    test('contractions', () {
      expect(lemmatizer.lemma("can't"), 'can');
      expect(lemmatizer.lemma("won't"), 'will');
      expect(lemmatizer.lemma("they'll"), "they'll");
      expect(lemmatizer.lemma("ran's"), 'run');
    });

    test('leading or trailing hyphen is not split', () {
      expect(lemmatizer.lemma('-running'), '-running');
      expect(lemmatizer.lemma('running-'), 'running-');
    });
  });

  group('cache', () {
    test('repeated query is not duplicated', () {
      lemmatizer
        ..lemma('went')
        ..lemma('went')
        ..lemma('WENT');
      expect(lemmatizer.cachedCount, 1);
    });

    test('pos is part of the cache key', () {
      lemmatizer
        ..lemma('better')
        ..lemma('better', pos: 'adv');
      expect(lemmatizer.cachedCount, 2);
      expect(lemmatizer.lemma('better'), 'good');
      expect(lemmatizer.lemma('better', pos: 'adv'), 'well');
    });

    test('default size is 1000 and never exceeded', () {
      expect(lemmatizer.cacheSize, 1000);
      for (var i = 0; i < 1500; i++) {
        lemmatizer.lemma('word$i');
      }
      expect(lemmatizer.cachedCount, 1000);
      expect(lemmatizer.isCached('word0'), isFalse);
      expect(lemmatizer.isCached('word499'), isFalse);
      expect(lemmatizer.isCached('word500'), isTrue);
      expect(lemmatizer.isCached('word1499'), isTrue);
    });

    test('least recently used entry is evicted first', () {
      final small = FormsLemmatizer.open(_pack, cacheSize: 3);
      addTearDown(small.close);
      small
        ..lemma('went')
        ..lemma('ran')
        ..lemma('took')
        ..lemma('went') // touched: 'ran' is now the oldest
        ..lemma('gone'); // evicts 'ran'
      expect(small.cachedCount, 3);
      expect(small.isCached('ran'), isFalse);
      expect(small.isCached('went'), isTrue);
      expect(small.isCached('took'), isTrue);
      expect(small.isCached('gone'), isTrue);
    });

    test('unknown words are cached too', () {
      lemmatizer.lemma('Zyzzyva');
      expect(lemmatizer.isCached('zyzzyva'), isTrue);
    });
  });

  test('use after close throws', () {
    final other = FormsLemmatizer.open(_pack)
      ..lemma('went')
      ..close();
    expect(() => other.lemma('went'), throwsStateError);
    other.close(); // idempotent
  });

  test('missing pack file throws', () {
    expect(
      () => FormsLemmatizer.open('no/such/file.sqlite'),
      throwsA(isA<SqliteException>()),
    );
  });

  group('EnglishTextAnalyzer', () {
    test('lemma delegates to the lemmatizer', () {
      final analyzer = EnglishTextAnalyzer(lemmatizer: lemmatizer);
      expect(analyzer.lemma('Running'), 'run');
      expect(analyzer.lemma('Zyzzyva'), 'zyzzyva');
    });

    test('without a lemmatizer keeps the lower-case behaviour', () {
      const analyzer = EnglishTextAnalyzer();
      expect(analyzer.lemma('Running'), 'running');
      expect(analyzer.lemma('Don’t'), "don't");
    });
  });
}
