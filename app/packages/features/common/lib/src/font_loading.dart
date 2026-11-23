import 'dart:convert';
import 'dart:io';

import 'package:core/domain_lookup.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('FontLoading');

/// Family and style names read from the `name` table of a font file.
final class FontName {
  /// Creates a name; [style] may be empty.
  const new({required this.family, required this.style});

  /// Family name (nameID 16, otherwise 1).
  final String family;

  /// Style name (nameID 17, otherwise 2), or an empty string.
  final String style;

  /// Name for lists and for registering the font: `Family Style`.
  String get display => style.isEmpty ? family : '$family $style';
}

/// Reads [length] bytes at [offset]; may return fewer at the end of a file.
typedef FontBytesReader = Future<Uint8List> Function(int offset, int length);

const int _maxTables = 128;
const int _maxNameTableBytes = 1024 * 1024;

/// Reads the family and style names of a TrueType or OpenType font held in
/// memory; `null` when it is not such a font or has no usable names.
Future<FontName?> parseFontName(Uint8List bytes) => readFontName(
  (offset, length) async => offset >= bytes.length
      ? Uint8List(0)
      : Uint8List.sublistView(
          bytes,
          offset,
          offset + length > bytes.length ? bytes.length : offset + length,
        ),
);

/// Reads the names of the font file at [path] without loading the whole file.
///
/// Never throws: a missing, unreadable or broken file gives `null`.
Future<FontName?> readFontNameFromFile(String path) async {
  RandomAccessFile? file;
  try {
    file = await File(path).open();
    final open = file;
    return await readFontName(
      (offset, length) =>
          open.setPosition(offset).then((_) => open.read(length)),
    );
  } on FileSystemException catch (e, s) {
    _log.fine('Cannot read the font $path', e, s);
    return null;
  } finally {
    await file?.close();
  }
}

/// Reads the `name` table through [read]; `null` for anything that is not a
/// well-formed `.ttf`/`.otf` (`.ttc` collections included).
Future<FontName?> readFontName(FontBytesReader read) async {
  final header = await read(0, 12);
  if (header.length < 12) return null;
  final head = ByteData.sublistView(header);
  final version = head.getUint32(0);
  const isTrueType = 0x00010000;
  const isOpenType = 0x4F54544F; // 'OTTO'
  const isApple = 0x74727565; // 'true'
  if (version != isTrueType && version != isOpenType && version != isApple) {
    return null;
  }
  final tables = head.getUint16(4);
  if (tables == 0 || tables > _maxTables) return null;
  final directory = await read(12, tables * 16);
  if (directory.length < tables * 16) return null;
  final dir = ByteData.sublistView(directory);
  for (var i = 0; i < tables; i++) {
    final at = i * 16;
    if (dir.getUint32(at) != 0x6E616D65) continue; // 'name'
    final offset = dir.getUint32(at + 8);
    final length = dir.getUint32(at + 12);
    if (length < 6 || length > _maxNameTableBytes) return null;
    final table = await read(offset, length);
    if (table.length < length) return null;
    return _parseNameTable(table);
  }
  return null;
}

FontName? _parseNameTable(Uint8List table) {
  final data = ByteData.sublistView(table);
  final count = data.getUint16(2);
  final storage = data.getUint16(4);
  if (6 + count * 12 > table.length) return null;
  // Best candidate per nameID: Windows English first, then any Windows or
  // Unicode record, then Macintosh Roman.
  final found = <int, (int, String)>{};
  for (var i = 0; i < count; i++) {
    final at = 6 + i * 12;
    final platform = data.getUint16(at);
    final encoding = data.getUint16(at + 2);
    final language = data.getUint16(at + 4);
    final id = data.getUint16(at + 6);
    if (id != 1 && id != 2 && id != 16 && id != 17) continue;
    final length = data.getUint16(at + 8);
    final start = storage + data.getUint16(at + 10);
    if (start + length > table.length) continue;
    final raw = Uint8List.sublistView(table, start, start + length);
    final String text;
    final int rank;
    if (platform == 3 || platform == 0) {
      text = _utf16be(raw);
      rank = platform == 3 && language == 0x409 ? 3 : 2;
    } else if (platform == 1 && encoding == 0) {
      text = latin1.decode(raw, allowInvalid: true);
      rank = 1;
    } else {
      continue;
    }
    final known = found[id];
    if (text.trim().isNotEmpty && (known == null || known.$1 < rank)) {
      found[id] = (rank, text.trim());
    }
  }
  final family = found[16]?.$2 ?? found[1]?.$2;
  if (family == null) return null;
  return FontName(family: family, style: found[17]?.$2 ?? found[2]?.$2 ?? '');
}

String _utf16be(Uint8List raw) => String.fromCharCodes([
  for (var i = 0; i + 1 < raw.length; i += 2) (raw[i] << 8) | raw[i + 1],
]);

final Set<String> _loaded = <String>{};

/// Registers [font] with the engine under its family name, so that a
/// `TextStyle(fontFamily: font.family)` draws with it.
///
/// Returns whether the font is usable. A missing or broken file gives `false`
/// and a `warning` in the log, never an exception; the caller then draws with
/// the system font. A font already registered is not read again.
Future<bool> loadUserFont(FontChoice font) async {
  final key = '${font.family}\u0000${font.path}';
  if (_loaded.contains(key)) return true;
  try {
    final file = File(font.path);
    if (!file.existsSync()) {
      _log.warning('Font file is missing, using the system font: ${font.path}');
      return false;
    }
    final bytes = await file.readAsBytes();
    final loader = FontLoader(font.family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loaded.add(key);
    return true;
  } on Exception catch (e, s) {
    _log.warning('Cannot load the font ${font.path}, using the system', e, s);
    return false;
  }
}
