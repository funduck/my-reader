import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lookup_stardict/lookup_stardict.dart';
import 'package:test/test.dart';

import 'fixtures/build.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

StarDictArticle _read(StarDictDict dict, StarDictIndex idx, String word) =>
    dict.read(idx.lookup(word).single);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('stardict_dict_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('StarDictArticle.parse', () {
    test('sametypesequence m: whole article is one text field', () {
      final a = StarDictArticle.parse(_bytes('plain\ntext'), 'm');
      expect(a.fields, [const StarDictField('m', 'plain\ntext')]);
    });

    test('sametypesequence h: HTML is kept as is', () {
      final a = StarDictArticle.parse(_bytes('<b>bold</b> &amp; more'), 'h');
      expect(a.fields, [const StarDictField('h', '<b>bold</b> &amp; more')]);
    });

    test('sametypesequence x: tags are stripped', () {
      final a = StarDictArticle.parse(
        _bytes('<k>cat</k><def><deftext>a &lt;small&gt; pet</deftext></def>'),
        'x',
      );
      expect(a.fields, [const StarDictField('x', 'cata <small> pet')]);
    });

    test('several types: all but the last end with NUL', () {
      final bytes = Uint8List.fromList([
        ...utf8.encode('kæt'),
        0,
        ...utf8.encode('a pet'),
      ]);
      final a = StarDictArticle.parse(bytes, 'tm');
      expect(a.fields, [
        const StarDictField('t', 'kæt'),
        const StarDictField('m', 'a pet'),
      ]);
      expect(a.text, 'kæt\na pet');
    });

    test('without sametypesequence each field carries its type byte', () {
      final bytes = Uint8List.fromList([
        ...utf8.encode('m'),
        ...utf8.encode('first'),
        0,
        ...utf8.encode('h'),
        ...utf8.encode('<i>second</i>'),
        0,
        ...utf8.encode('x'),
        ...utf8.encode('<k>third</k>'),
      ]);
      final a = StarDictArticle.parse(bytes, null);
      expect(a.fields, [
        const StarDictField('m', 'first'),
        const StarDictField('h', '<i>second</i>'),
        const StarDictField('x', 'third'),
      ]);
    });

    test('binary fields are skipped', () {
      final bytes = Uint8List.fromList([
        ...utf8.encode('m'),
        ...utf8.encode('text'),
        0,
        ...utf8.encode('W'),
        0,
        0,
        0,
        3,
        1,
        2,
        3,
        ...utf8.encode('m'),
        ...utf8.encode('after'),
        0,
      ]);
      final a = StarDictArticle.parse(bytes, null);
      expect(a.fields.map((f) => f.text), ['text', 'after']);
    });

    test('truncated binary field throws FormatException', () {
      final bytes = Uint8List.fromList([...utf8.encode('W'), 0, 0, 0, 9, 1]);
      expect(
        () => StarDictArticle.parse(bytes, null),
        throwsA(isA<FormatException>()),
      );
    });

    test('invalid UTF-8 does not throw', () {
      final a = StarDictArticle.parse(Uint8List.fromList([0xFF, 0x41]), 'm');
      expect(a.fields.single.text, endsWith('A'));
    });
  });

  group('StarDictDict', () {
    const entries = [
      FixtureEntry('apple', 'a red fruit'),
      FixtureEntry('banana', 'a yellow fruit'),
      FixtureEntry('über', 'ünïcode — 日本語'),
    ];

    void readsAll(StarDictDict dict, StarDictIndex idx) {
      expect(_read(dict, idx, 'apple').text, 'a red fruit');
      expect(_read(dict, idx, 'banana').text, 'a yellow fruit');
      expect(_read(dict, idx, 'über').text, 'ünïcode — 日本語');
    }

    for (final type in ['m', 'h']) {
      test('plain .dict, sametypesequence=$type', () {
        final f = buildStarDict(entries, sameTypeSequence: type);
        final base = f.writeTo(tmp.path);
        final info = StarDictInfo.parse(f.ifo);
        final dict = StarDictDict.open('$base.dict', info);
        addTearDown(dict.close);
        final idx = StarDictIndex.parse(f.idx, info);
        readsAll(dict, idx);
        expect(_read(dict, idx, 'apple').fields.single.type, type);
      });

      test('.dict.dz unpacked once, sametypesequence=$type', () async {
        final f = buildStarDict(entries, sameTypeSequence: type);
        final base = f.writeDzTo(tmp.path);
        expect(File('$base.dict').existsSync(), isFalse);
        await decompressDictDz('$base.dict.dz', '$base.dict');
        expect(File('$base.dict').readAsBytesSync(), f.dict);
        final info = StarDictInfo.parse(f.ifo);
        final dict = StarDictDict.open('$base.dict', info);
        addTearDown(dict.close);
        readsAll(dict, StarDictIndex.parse(f.idx, info));
      });
    }

    test('xdxf articles come back without tags', () {
      final f = buildStarDict([
        const FixtureEntry('cat', '<k>cat</k><def>a pet</def>'),
      ], sameTypeSequence: 'x');
      final base = f.writeTo(tmp.path);
      final info = StarDictInfo.parse(f.ifo);
      final dict = StarDictDict.open('$base.dict', info);
      addTearDown(dict.close);
      final idx = StarDictIndex.parse(f.idx, info);
      expect(_read(dict, idx, 'cat').text, 'cata pet');
    });

    test('no sametypesequence: types stored in each article', () {
      final f = buildStarDict([
        FixtureEntry(
          'cat',
          '',
          rawBytes: [...utf8.encode('mmeow'), 0, ...utf8.encode('h<b>x</b>')],
        ),
      ], sameTypeSequence: null);
      final base = f.writeTo(tmp.path);
      final info = StarDictInfo.parse(f.ifo);
      expect(info.sameTypeSequence, isNull);
      final dict = StarDictDict.open('$base.dict', info);
      addTearDown(dict.close);
      final idx = StarDictIndex.parse(f.idx, info);
      expect(_read(dict, idx, 'cat').fields, [
        const StarDictField('m', 'meow'),
        const StarDictField('h', '<b>x</b>'),
      ]);
    });

    test('entry outside the file throws FormatException', () {
      final f = buildStarDict(entries);
      final base = f.writeTo(tmp.path);
      final dict = StarDictDict.open('$base.dict', StarDictInfo.parse(f.ifo));
      addTearDown(dict.close);
      expect(dict.length, f.dict.length);
      expect(
        () => dict.read(StarDictEntry('x', f.dict.length - 1, 5)),
        throwsA(isA<FormatException>()),
      );
    });

    test('invalid .dict.dz throws FormatException, leaves no .dict', () async {
      final dz = File('${tmp.path}/bad.dict.dz')
        ..writeAsBytesSync(utf8.encode('this is not gzip'));
      await expectLater(
        decompressDictDz(dz.path, '${tmp.path}/bad.dict'),
        throwsA(isA<FormatException>()),
      );
      expect(File('${tmp.path}/bad.dict').existsSync(), isFalse);
    });
  });
}
