import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lookup_stardict/lookup_stardict.dart';

/// A headword and its article text for [buildStarDict].
class FixtureEntry {
  /// Creates an entry.
  const new(this.word, this.article);

  /// Headword.
  final String word;

  /// Article, stored in `.dict` as UTF-8.
  final String article;
}

/// The three files of a tiny StarDict dictionary, built in memory.
class StarDictFixture {
  /// Creates a fixture from its parts.
  const new({
    required this.ifo,
    required this.idx,
    required this.dict,
    required this.entries,
  });

  /// Text of the `.ifo` file.
  final String ifo;

  /// Bytes of the `.idx` file, sorted as StarDict sorts it.
  final Uint8List idx;

  /// Bytes of the `.dict` file (articles back to back).
  final Uint8List dict;

  /// Entries in `.idx` order.
  final List<StarDictEntry> entries;

  /// Writes `<name>.ifo`, `<name>.idx` and `<name>.dict` into [dir]
  /// (created if missing) and returns the path without extension.
  String writeTo(String dir, [String name = 'test']) {
    Directory(dir).createSync(recursive: true);
    final base = '$dir/$name';
    File('$base.ifo').writeAsStringSync(ifo);
    File('$base.idx').writeAsBytesSync(idx);
    File('$base.dict').writeAsBytesSync(dict);
    return base;
  }
}

/// Builds a tiny StarDict dictionary from [entries].
///
/// Articles are laid out in the order given; the `.idx` is sorted with
/// [stardictCompare] (stable, so equal words keep the given order).
/// [offsetBits] is 32 or 64. [offsetShift] is added to every offset written
/// to `.idx` without moving the articles: it lets a test exercise offsets
/// above 2^32 without a multi-gigabyte `.dict`.
StarDictFixture buildStarDict(
  List<FixtureEntry> entries, {
  int offsetBits = 32,
  int offsetShift = 0,
  String bookName = 'Test dictionary',
  String? sameTypeSequence = 'm',
  String version = '2.4.2',
}) {
  final dict = BytesBuilder();
  final raw = <StarDictEntry>[];
  for (final e in entries) {
    final article = utf8.encode(e.article);
    raw.add(StarDictEntry(e.word, dict.length + offsetShift, article.length));
    dict.add(article);
  }
  final order = List<int>.generate(raw.length, (i) => i)
    ..sort((a, b) {
      final c = stardictCompare(raw[a].word, raw[b].word);
      return c != 0 ? c : a - b;
    });
  final sorted = [for (final i in order) raw[i]];

  final idx = BytesBuilder();
  for (final e in sorted) {
    idx
      ..add(utf8.encode(e.word))
      ..addByte(0);
    final offset = ByteData(offsetBits ~/ 8);
    if (offsetBits == 64) {
      offset.setUint64(0, e.offset);
    } else {
      offset.setUint32(0, e.offset);
    }
    final size = ByteData(4)..setUint32(0, e.size);
    idx
      ..add(offset.buffer.asUint8List())
      ..add(size.buffer.asUint8List());
  }
  final idxBytes = idx.toBytes();

  final ifo = StringBuffer()
    ..writeln("StarDict's dict ifo file")
    ..writeln('version=$version')
    ..writeln('bookname=$bookName')
    ..writeln('wordcount=${sorted.length}')
    ..writeln('idxfilesize=${idxBytes.length}');
  if (offsetBits != 32) ifo.writeln('idxoffsetbits=$offsetBits');
  if (sameTypeSequence != null) {
    ifo.writeln('sametypesequence=$sameTypeSequence');
  }
  return StarDictFixture(
    ifo: ifo.toString(),
    idx: idxBytes,
    dict: dict.toBytes(),
    entries: sorted,
  );
}
