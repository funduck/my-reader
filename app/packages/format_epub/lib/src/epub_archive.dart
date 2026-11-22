import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'epub_path.dart';

/// Path of the container descriptor every EPUB must have.
const containerXmlPath = 'META-INF/container.xml';

/// The ZIP file of an EPUB: read-only access to entries by name.
final class EpubArchive {
  new _(this._files);

  /// Parses [bytes] as a ZIP file.
  ///
  /// Throws [FormatException] when the data is not a readable ZIP archive.
  factory fromBytes(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object catch (e) {
      throw FormatException('Not a ZIP archive: $e');
    }
    final files = <String, ArchiveFile>{};
    for (final file in archive) {
      if (!file.isFile) continue;
      final name = normalizeEntryPath(file.name);
      if (name != null && name.isNotEmpty) files[name] = file;
    }
    return EpubArchive._(files);
  }

  final Map<String, ArchiveFile> _files;

  /// Whether an entry with this (already normalized) name exists.
  bool contains(String path) => _files.containsKey(path);

  /// Entry names, in archive order.
  Iterable<String> get names => _files.keys;

  /// Bytes of the entry [path]; throws [FormatException] when it is absent.
  Uint8List read(String path) {
    final file = _files[path];
    if (file == null) {
      throw FormatException('No such entry in the EPUB: $path');
    }
    try {
      return file.readBytes() ?? Uint8List(0);
    } on Object catch (e) {
      throw FormatException('Cannot unpack $path: $e');
    }
  }

  /// Entry [path] decoded as text.
  ///
  /// UTF-8 (a BOM is dropped) and UTF-16 (by BOM) are decoded strictly;
  /// `ISO-8859-1` / `latin1` declared in an XML prolog is decoded as Latin-1.
  /// Any other declared encoding and malformed UTF-8 give a
  /// [FormatException] naming the encoding and the entry: text is never
  /// silently replaced with U+FFFD.
  String readText(String path) => _decodeText(read(path), path);

  /// Parses the entry [path] as XML; [FormatException] on malformed XML.
  XmlDocument readXml(String path) => parseXml(readText(path), path);

  /// Finds the path of the package document (OPF) via `container.xml`.
  ///
  /// Throws [FormatException] when the container or its rootfile is missing.
  String findPackagePath() {
    if (!contains(containerXmlPath)) {
      throw const FormatException('Not an EPUB: no META-INF/container.xml');
    }
    final doc = readXml(containerXmlPath);
    for (final element in doc.descendantElements) {
      if (element.name.local != 'rootfile') continue;
      final type = element.getAttribute('media-type');
      if (type != null && type != 'application/oebps-package+xml') continue;
      final fullPath = element.getAttribute('full-path');
      final path = fullPath == null ? null : normalizeEntryPath(fullPath);
      if (path != null && path.isNotEmpty) return path;
    }
    throw const FormatException('container.xml names no package document');
  }
}

/// Parses [source] as XML, mapping parser errors to [FormatException].
///
/// Named HTML entities (`&nbsp;`, `&mdash;`) are decoded, as real EPUBs use
/// them without declaring them.
XmlDocument parseXml(String source, String what) {
  try {
    return XmlDocument.parse(
      source,
      entityMapping: const XmlDefaultEntityMapping.html(),
    );
  } on XmlException catch (e) {
    throw FormatException('Malformed XML in $what: ${e.message}');
  }
}

final RegExp _declaredEncoding = RegExp(
  r'''^<\?xml[^>]*?\sencoding\s*=\s*["']([^"']+)["']''',
);

const _utf8Names = {'utf-8', 'utf8', 'us-ascii', 'ascii'};
const _latin1Names = {
  'iso-8859-1',
  'iso8859-1',
  'iso_8859-1',
  'latin1',
  'latin-1',
  'l1',
};

String _decodeText(Uint8List bytes, String path) {
  if (bytes.length >= 2) {
    final bigEndian = bytes[0] == 0xfe && bytes[1] == 0xff;
    final littleEndian = bytes[0] == 0xff && bytes[1] == 0xfe;
    if (bigEndian || littleEndian) {
      return _decodeUtf16(bytes, path, bigEndian: bigEndian);
    }
  }
  var start = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf) {
    start = 3;
  }
  final head = String.fromCharCodes(
    bytes.sublist(start, (start + 200).clamp(0, bytes.length)),
  );
  final declared = _declaredEncoding.firstMatch(head)?.group(1);
  final name = declared?.toLowerCase();
  if (name != null && _latin1Names.contains(name)) {
    return latin1.decode(bytes.sublist(start));
  }
  if (name != null && !_utf8Names.contains(name)) {
    throw FormatException('Unsupported encoding "$declared" in $path');
  }
  try {
    return utf8.decode(bytes.sublist(start));
  } on FormatException catch (e) {
    throw FormatException('Invalid UTF-8 in $path: ${e.message}');
  }
}

String _decodeUtf16(Uint8List bytes, String path, {required bool bigEndian}) {
  final body = bytes.length - 2;
  if (body.isOdd) {
    throw FormatException('Truncated UTF-16 text in $path');
  }
  final units = [
    for (var i = 2; i < bytes.length; i += 2)
      if (bigEndian)
        (bytes[i] << 8) | bytes[i + 1]
      else
        (bytes[i + 1] << 8) | bytes[i],
  ];
  return String.fromCharCodes(units);
}
