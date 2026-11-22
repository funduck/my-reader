import 'package:lookup_stardict/lookup_stardict.dart';
import 'package:test/test.dart';

const _full = '''
StarDict's dict ifo file
version=3.0.0
bookname=Full Dict
wordcount=12
synwordcount=3
idxfilesize=345
idxoffsetbits=64
author=An Author
email=a@example.com
website=https://example.com
description=Some text with = sign
date=2024-01-02
sametypesequence=h
dicttype=wordnet
unknown=ignored
''';

void main() {
  group('StarDictInfo.parse', () {
    test('reads every listed field', () {
      final info = StarDictInfo.parse(_full);
      expect(info.version, '3.0.0');
      expect(info.bookName, 'Full Dict');
      expect(info.wordCount, 12);
      expect(info.synWordCount, 3);
      expect(info.idxFileSize, 345);
      expect(info.idxOffsetBits, 64);
      expect(info.offsetBytes, 8);
      expect(info.author, 'An Author');
      expect(info.email, 'a@example.com');
      expect(info.website, 'https://example.com');
      expect(info.description, 'Some text with = sign');
      expect(info.date, '2024-01-02');
      expect(info.sameTypeSequence, 'h');
      expect(info.dictType, 'wordnet');
    });

    test('optional fields default; offset bits 32', () {
      final info = StarDictInfo.parse(
        "StarDict's dict ifo file\r\nversion=2.4.2\r\nbookname=B\r\n"
        'wordcount=1\r\nidxfilesize=10\r\n',
      );
      expect(info.idxOffsetBits, 32);
      expect(info.offsetBytes, 4);
      expect(info.synWordCount, isNull);
      expect(info.sameTypeSequence, isNull);
      expect(info.author, isNull);
    });

    test('accepts a BOM', () {
      final info = StarDictInfo.parse(
        "﻿StarDict's dict ifo file\nversion=2.4.2\nbookname=B\n"
        'wordcount=1\nidxfilesize=10\n',
      );
      expect(info.bookName, 'B');
    });

    final bad = <String, String>{
      'empty': '',
      'bad magic': 'Something else\nversion=2.4.2\n',
      'line without =': "StarDict's dict ifo file\nversion\n",
      'missing version':
          "StarDict's dict ifo file\nbookname=B\nwordcount=1\nidxfilesize=1\n",
      'missing bookname':
          "StarDict's dict ifo file\nversion=2.4.2\nwordcount=1\n"
          'idxfilesize=1\n',
      'missing wordcount':
          "StarDict's dict ifo file\nversion=2.4.2\nbookname=B\n"
          'idxfilesize=1\n',
      'missing idxfilesize':
          "StarDict's dict ifo file\nversion=2.4.2\nbookname=B\nwordcount=1\n",
      'non-numeric wordcount':
          "StarDict's dict ifo file\nversion=2.4.2\nbookname=B\n"
          'wordcount=many\nidxfilesize=1\n',
      'negative idxfilesize':
          "StarDict's dict ifo file\nversion=2.4.2\nbookname=B\n"
          'wordcount=1\nidxfilesize=-1\n',
      'unsupported idxoffsetbits':
          "StarDict's dict ifo file\nversion=2.4.2\nbookname=B\n"
          'wordcount=1\nidxfilesize=1\nidxoffsetbits=16\n',
    };
    for (final entry in bad.entries) {
      test('malformed (${entry.key}) throws FormatException', () {
        expect(
          () => StarDictInfo.parse(entry.value),
          throwsA(isA<FormatException>()),
        );
      });
    }
  });
}
