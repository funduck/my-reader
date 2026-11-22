import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'stardict_compare.dart';
import 'stardict_ifo.dart';

/// One `.idx` entry: a headword and where its article lies in `.dict`.
@immutable
class StarDictEntry {
  /// Creates an entry.
  const new(this.word, this.offset, this.size);

  /// Headword, decoded from UTF-8.
  final String word;

  /// Byte offset of the article in the uncompressed `.dict` file.
  final int offset;

  /// Article length in bytes.
  final int size;

  @override
  bool operator ==(Object other) =>
      other is StarDictEntry &&
      other.word == word &&
      other.offset == offset &&
      other.size == size;

  @override
  int get hashCode => Object.hash(word, offset, size);

  @override
  String toString() => 'StarDictEntry($word, $offset, $size)';
}

/// The `.idx` file of a StarDict dictionary, held fully in memory, with a
/// binary search over it.
///
/// Only the raw bytes and one 32-bit start position per entry are kept; words
/// are decoded on demand. The file must be sorted as StarDict sorts it, see
/// [stardictCompare]; this is not verified.
class StarDictIndex {
  new _(this._bytes, this._starts, this._offsetBytes);

  /// Parses the bytes of an `.idx` file described by [info].
  ///
  /// Checks that the size equals `info.idxFileSize` and that exactly
  /// `info.wordCount` entries are found. Throws [FormatException] otherwise.
  factory parse(Uint8List bytes, StarDictInfo info) {
    if (bytes.length != info.idxFileSize) {
      throw FormatException(
        '.idx size ${bytes.length} differs from idxfilesize '
        '${info.idxFileSize}',
      );
    }
    final offsetBytes = info.offsetBytes;
    final starts = Uint32List(info.wordCount);
    var pos = 0;
    var count = 0;
    while (pos < bytes.length) {
      if (count >= info.wordCount) {
        throw FormatException(
          '.idx holds more than wordcount (${info.wordCount}) entries',
        );
      }
      starts[count++] = pos;
      final nul = bytes.indexOf(0, pos);
      if (nul < 0 || nul == pos) {
        throw FormatException(
          nul == pos ? 'Empty word in .idx' : 'Unterminated word in .idx',
          pos,
        );
      }
      pos = nul + 1 + offsetBytes + 4;
      if (pos > bytes.length) {
        throw FormatException('Truncated entry in .idx', nul);
      }
    }
    if (count != info.wordCount) {
      throw FormatException(
        '.idx holds $count entries, wordcount is ${info.wordCount}',
      );
    }
    return StarDictIndex._(bytes, starts, offsetBytes);
  }

  /// Reads the `.idx` file at [path] and parses it with [info].
  ///
  /// Throws [FormatException] for a malformed file and [FileSystemException]
  /// if it cannot be read.
  static Future<StarDictIndex> open(String path, StarDictInfo info) async =>
      StarDictIndex.parse(await File(path).readAsBytes(), info);

  final Uint8List _bytes;
  final Uint32List _starts;
  final int _offsetBytes;

  /// Number of entries.
  int get length => _starts.length;

  int _wordEnd(int index) {
    final start = _starts[index];
    return _bytes.indexOf(0, start);
  }

  /// The entry at [index] in file order (`0 <= index < length`).
  ///
  /// Throws [RangeError] otherwise.
  StarDictEntry operator [](int index) {
    RangeError.checkValidIndex(index, _starts, 'index', length);
    final start = _starts[index];
    final end = _wordEnd(index);
    final data = ByteData.sublistView(_bytes, end + 1);
    final offset = _offsetBytes == 8 ? data.getUint64(0) : data.getUint32(0);
    final size = data.getUint32(_offsetBytes);
    return StarDictEntry(
      utf8.decode(_bytes.sublist(start, end), allowMalformed: true),
      offset,
      size,
    );
  }

  /// All entries in file order.
  Iterable<StarDictEntry> get entries sync* {
    for (var i = 0; i < length; i++) {
      yield this[i];
    }
  }

  /// Entries whose word equals [word] ignoring ASCII case, in file order.
  ///
  /// Only `A`-`Z` fold, exactly as in StarDict: `Apple`, `APPLE` and `apple`
  /// match each other, `É` and `é` do not. Entries with the same spelling as
  /// [word] come first, so `lookup(word).firstOrNull` is the best match.
  /// Returns an empty list when nothing matches.
  List<StarDictEntry> lookup(String word) {
    final key = Uint8List.fromList(utf8.encode(word));
    if (key.isEmpty) return const [];
    // Lower bound by the case-insensitive part only.
    var lo = 0;
    var hi = length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_compareFolded(mid, key) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final found = <StarDictEntry>[];
    for (var i = lo; i < length && _compareFolded(i, key) == 0; i++) {
      found.add(this[i]);
    }
    final exact = found.where((e) => e.word == word).toList();
    if (exact.isEmpty || exact.length == found.length) return found;
    return [...exact, ...found.where((e) => e.word != word)];
  }

  /// ASCII case-insensitive comparison of entry [index] with [key].
  int _compareFolded(int index, Uint8List key) {
    final start = _starts[index];
    final end = _wordEnd(index);
    final aLen = end - start;
    final common = aLen < key.length ? aLen : key.length;
    for (var i = 0; i < common; i++) {
      final d = _fold(_bytes[start + i]) - _fold(key[i]);
      if (d != 0) return d;
    }
    return aLen - key.length;
  }

  static int _fold(int b) => b >= 0x41 && b <= 0x5A ? b + 0x20 : b;
}
