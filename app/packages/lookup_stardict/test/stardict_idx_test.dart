import 'dart:io';
import 'dart:typed_data';

import 'package:lookup_stardict/lookup_stardict.dart';
import 'package:test/test.dart';

import 'fixtures/build.dart';

const _words = [
  FixtureEntry('banana', 'a yellow fruit'),
  FixtureEntry('Apple', 'a red fruit, capitalised'),
  FixtureEntry('apple', 'a red fruit'),
  FixtureEntry('cherry', 'a small fruit'),
  FixtureEntry('Zebra', 'striped animal'),
  FixtureEntry('über', 'above (UTF-8)'),
  FixtureEntry('日本語', 'Japanese'),
  FixtureEntry('APPLE', 'shouted apple'),
];

StarDictIndex _index(StarDictFixture f) =>
    StarDictIndex.parse(f.idx, StarDictInfo.parse(f.ifo));

void main() {
  group('stardictCompare', () {
    test('case-insensitive first, case-sensitive as tiebreak', () {
      expect(stardictCompare('apple', 'Banana'), isNegative);
      expect(stardictCompare('Apple', 'apple'), isNegative); // 'A' < 'a'
      expect(stardictCompare('APPLE', 'Apple'), isNegative);
      expect(stardictCompare('apple', 'apple'), isZero);
      expect(stardictCompare('apple', 'apples'), isNegative);
      expect(stardictCompare('Zebra', 'apple'), isPositive);
    });

    test('non-ASCII bytes are not folded', () {
      expect(stardictCompare('é', 'É'), isPositive);
      expect(stardictCompare('z', 'é'), isNegative);
    });
  });

  for (final bits in [32, 64]) {
    group('StarDictIndex, $bits-bit offsets', () {
      late StarDictFixture fixture;
      late StarDictIndex index;

      setUp(() {
        fixture = buildStarDict(_words, offsetBits: bits);
        index = _index(fixture);
      });

      test('keeps the order of the file', () {
        expect(index.length, _words.length);
        expect(index.entries.toList(), fixture.entries);
        expect(index.entries.map((e) => e.word).toList(), [
          'APPLE',
          'Apple',
          'apple',
          'banana',
          'cherry',
          'Zebra',
          'über',
          '日本語',
        ]);
      });

      test('finds an existing word and returns offset and size', () {
        final hit = index.lookup('banana').single;
        expect(hit.word, 'banana');
        expect(
          String.fromCharCodes(
            fixture.dict.sublist(hit.offset, hit.offset + hit.size),
          ),
          'a yellow fruit',
        );
      });

      test('first and last entries are found', () {
        expect(index[0].word, 'APPLE');
        expect(index.lookup('APPLE').first.word, 'APPLE');
        expect(index[index.length - 1].word, '日本語');
        expect(index.lookup('日本語').single.word, '日本語');
      });

      test('UTF-8 words', () {
        expect(index.lookup('über').single.size, 'above (UTF-8)'.length);
      });

      test('missing words give an empty list', () {
        expect(index.lookup('aardvark'), isEmpty);
        expect(index.lookup('zzz'), isEmpty);
        expect(index.lookup('app'), isEmpty);
        expect(index.lookup('applesauce'), isEmpty);
        expect(index.lookup(''), isEmpty);
        expect(index.lookup('Über'), isEmpty); // non-ASCII is not folded
      });

      test('different case finds all variants, exact spelling first', () {
        expect(index.lookup('apple').map((e) => e.word), [
          'apple',
          'APPLE',
          'Apple',
        ]);
        expect(index.lookup('APPLE').map((e) => e.word), [
          'APPLE',
          'Apple',
          'apple',
        ]);
        expect(index.lookup('aPPle').map((e) => e.word), [
          'APPLE',
          'Apple',
          'apple',
        ]);
        expect(index.lookup('ZEBRA').single.word, 'Zebra');
        expect(index.lookup('Banana').single.word, 'banana');
      });

      test('every word is found by binary search', () {
        for (final e in fixture.entries) {
          expect(index.lookup(e.word).first, e);
        }
      });

      test('operator [] checks the range', () {
        expect(() => index[-1], throwsRangeError);
        expect(() => index[index.length], throwsRangeError);
      });
    });
  }

  test('64-bit offsets above 2^32', () {
    const shift = 0x1FFFFFFFF0;
    final fixture = buildStarDict(_words, offsetBits: 64, offsetShift: shift);
    final index = _index(fixture);
    final hit = index.lookup('cherry').single;
    expect(hit.offset, greaterThan(0xFFFFFFFF));
    expect(
      hit.offset,
      fixture.entries.firstWhere((e) => e.word == 'cherry').offset,
    );
    expect(hit.offset - shift, isNonNegative);
  });

  test('an empty dictionary is valid', () {
    final index = _index(buildStarDict(const []));
    expect(index.length, 0);
    expect(index.lookup('a'), isEmpty);
  });

  group('malformed .idx throws FormatException', () {
    final good = buildStarDict(_words);
    final info = StarDictInfo.parse(good.ifo);

    test('size differs from idxfilesize', () {
      final cut = Uint8List.sublistView(good.idx, 0, good.idx.length - 1);
      expect(
        () => StarDictIndex.parse(cut, info),
        throwsA(isA<FormatException>()),
      );
    });

    test('truncated last entry with a consistent idxfilesize', () {
      final cut = Uint8List.sublistView(good.idx, 0, good.idx.length - 3);
      final cutInfo = StarDictInfo.parse(
        good.ifo.replaceFirst(
          'idxfilesize=${good.idx.length}',
          'idxfilesize=${cut.length}',
        ),
      );
      expect(
        () => StarDictIndex.parse(cut, cutInfo),
        throwsA(isA<FormatException>()),
      );
    });

    test('wordcount differs from the number of entries', () {
      final other = StarDictInfo.parse(
        good.ifo.replaceFirst('wordcount=8', 'wordcount=7'),
      );
      expect(
        () => StarDictIndex.parse(good.idx, other),
        throwsA(isA<FormatException>()),
      );
      final more = StarDictInfo.parse(
        good.ifo.replaceFirst('wordcount=8', 'wordcount=9'),
      );
      expect(
        () => StarDictIndex.parse(good.idx, more),
        throwsA(isA<FormatException>()),
      );
    });

    test('word without terminating NUL', () {
      final bytes = Uint8List.fromList([0x61, 0x62, 0x63]);
      final i = StarDictInfo.parse(
        "StarDict's dict ifo file\nversion=2.4.2\nbookname=B\n"
        'wordcount=1\nidxfilesize=3\n',
      );
      expect(
        () => StarDictIndex.parse(bytes, i),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test('open reads the .idx file from disk', () async {
    final dir = Directory.systemTemp.createTempSync('stardict_idx_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final fixture = buildStarDict(_words, offsetBits: 64);
    final base = fixture.writeTo(dir.path);
    final info = StarDictInfo.parse(File('$base.ifo').readAsStringSync());
    final index = await StarDictIndex.open('$base.idx', info);
    expect(index.lookup('cherry').single.word, 'cherry');
  });
}
