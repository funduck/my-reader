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

  /// Entry [path] decoded as UTF-8 (a BOM is dropped, bad bytes replaced).
  String readText(String path) {
    final text = utf8.decode(read(path), allowMalformed: true);
    return text.startsWith('﻿') ? text.substring(1) : text;
  }

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
