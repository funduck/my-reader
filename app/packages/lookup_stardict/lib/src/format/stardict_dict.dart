import 'dart:io';
import 'dart:typed_data';

import 'stardict_article.dart';
import 'stardict_idx.dart';
import 'stardict_ifo.dart';

/// Unpacks a `.dict.dz` (gzip-compatible dictzip) file into [dictPath].
///
/// Meant to run once at import, so that [StarDictDict] can read the plain
/// `.dict` by offset. Streams the data, so the whole file is not held in
/// memory. Throws [FormatException] if [dzPath] is not valid gzip; a
/// half-written [dictPath] is deleted in that case.
Future<void> decompressDictDz(String dzPath, String dictPath) async {
  final sink = File(dictPath).openWrite();
  try {
    await sink.addStream(File(dzPath).openRead().transform(gzip.decoder));
    await sink.close();
  } on FileSystemException {
    await _discard(sink, dictPath);
    rethrow;
  } on Exception catch (e) {
    await _discard(sink, dictPath);
    throw FormatException('Cannot unpack .dict.dz: $e', dzPath);
  }
}

Future<void> _discard(IOSink sink, String path) async {
  try {
    await sink.close();
  } on Exception {
    // The sink already failed; the file is removed below anyway.
  }
  final file = File(path);
  if (file.existsSync()) file.deleteSync();
}

/// Random-access reader of an uncompressed StarDict `.dict` file.
class StarDictDict {
  new _(this._file, this.length, this._info);

  /// Opens the plain `.dict` at [path] for the dictionary described by [info].
  ///
  /// For a `.dict.dz` call [decompressDictDz] first. The caller owns the
  /// reader and must call [close].
  factory open(String path, StarDictInfo info) {
    final file = File(path).openSync();
    return StarDictDict._(file, file.lengthSync(), info);
  }

  final RandomAccessFile _file;
  final StarDictInfo _info;

  /// Size of the `.dict` file in bytes.
  final int length;

  /// Reads the article of [entry] and splits it into fields.
  ///
  /// Throws [FormatException] when the entry points outside the file.
  StarDictArticle read(StarDictEntry entry) {
    final end = entry.offset + entry.size;
    if (entry.offset < 0 || entry.size < 0 || end > length) {
      throw FormatException(
        'Article of "${entry.word}" lies outside .dict '
        '(offset ${entry.offset}, size ${entry.size}, file $length)',
      );
    }
    _file.setPositionSync(entry.offset);
    final bytes = _file.readSync(entry.size);
    if (bytes.length != entry.size) {
      throw FormatException('Short read of "${entry.word}" from .dict');
    }
    return StarDictArticle.parse(
      Uint8List.fromList(bytes),
      _info.sameTypeSequence,
    );
  }

  /// Closes the file.
  void close() => _file.closeSync();
}
