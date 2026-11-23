import 'dart:convert';
import 'dart:typed_data';

/// Builds a minimal sfnt file whose only table is `name`.
///
/// Enough for the `name` parser; not a font the engine can draw with. Each
/// record is `(platformId, nameId, text)`; Windows records are UTF-16BE,
/// Macintosh ones Latin-1.
Uint8List buildTestFont(
  List<(int, int, String)> records, {
  int version = 0x00010000,
}) {
  final strings = BytesBuilder();
  final entries = BytesBuilder();
  for (final (platform, id, text) in records) {
    final raw = platform == 1
        ? latin1.encode(text)
        : Uint8List.fromList([
            for (final unit in text.codeUnits) ...[unit >> 8, unit & 0xFF],
          ]);
    final head = ByteData(12)
      ..setUint16(0, platform)
      ..setUint16(2, platform == 1 ? 0 : 1)
      ..setUint16(4, platform == 3 ? 0x409 : 0)
      ..setUint16(6, id)
      ..setUint16(8, raw.length)
      ..setUint16(10, strings.length);
    entries.add(head.buffer.asUint8List());
    strings.add(raw);
  }
  final nameHeader = ByteData(6)
    ..setUint16(0, 0)
    ..setUint16(2, records.length)
    ..setUint16(4, 6 + records.length * 12);
  final table = BytesBuilder()
    ..add(nameHeader.buffer.asUint8List())
    ..add(entries.toBytes())
    ..add(strings.toBytes());
  final tableBytes = table.toBytes();
  final fileHeader = ByteData(12)
    ..setUint32(0, version)
    ..setUint16(4, 1);
  final record = ByteData(16)
    ..setUint32(0, 0x6E616D65)
    ..setUint32(8, 28)
    ..setUint32(12, tableBytes.length);
  return (BytesBuilder()
        ..add(fileHeader.buffer.asUint8List())
        ..add(record.buffer.asUint8List())
        ..add(tableBytes))
      .toBytes();
}
