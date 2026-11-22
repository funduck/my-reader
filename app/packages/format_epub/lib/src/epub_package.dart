import 'package:core/domain_books.dart';
import 'package:meta/meta.dart';
import 'package:xml/xml.dart';

import 'epub_archive.dart';
import 'epub_path.dart';

/// One `<item>` of the OPF manifest.
@immutable
final class ManifestItem {
  /// Creates an item; [path] is already a container entry name.
  const new({
    required this.id,
    required this.path,
    required this.mediaType,
    this.properties = const {},
  });

  /// `id` attribute, referenced by the spine.
  final String id;

  /// Container entry name (resolved against the OPF location, decoded).
  final String path;

  /// `media-type` attribute, lower-cased; empty when absent.
  final String mediaType;

  /// Space separated `properties` attribute (EPUB 3), e.g. `nav`.
  final Set<String> properties;

  @override
  bool operator ==(Object other) =>
      other is ManifestItem &&
      other.id == id &&
      other.path == path &&
      other.mediaType == mediaType &&
      other.properties.length == properties.length &&
      other.properties.containsAll(properties);

  @override
  int get hashCode => Object.hash(id, path, mediaType, properties.length);

  @override
  String toString() => 'ManifestItem($id, $path)';
}

/// Parsed package document (OPF): metadata, manifest and spine.
final class EpubPackage {
  /// Creates a package from parsed parts.
  const new({
    required this.path,
    required this.version,
    required this.metadata,
    required this.manifest,
    required this.spine,
    this.coverPath,
    this.ncxId,
  });

  /// Reads the package document at [opfPath] from [archive].
  ///
  /// [fallbackTitle] is used when the OPF names no title. Throws
  /// [FormatException] for a missing or malformed OPF or an empty spine.
  factory parse(
    EpubArchive archive,
    String opfPath, {
    required String fallbackTitle,
  }) {
    if (!archive.contains(opfPath)) {
      throw FormatException('Package document not found: $opfPath');
    }
    final root = archive.readXml(opfPath).rootElement;
    if (root.name.local != 'package') {
      throw FormatException('$opfPath is not an OPF package document');
    }
    final version = root.getAttribute('version') ?? '2.0';

    final manifest = <String, ManifestItem>{};
    for (final item in _children(_child(root, 'manifest'), 'item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      final path = resolveEntryPath(opfPath, href);
      if (path == null || path.isEmpty) continue;
      manifest[id] = ManifestItem(
        id: id,
        path: path,
        mediaType: (item.getAttribute('media-type') ?? '').toLowerCase(),
        properties: (item.getAttribute('properties') ?? '')
            .split(RegExp(r'\s+'))
            .where((p) => p.isNotEmpty)
            .toSet(),
      );
    }

    final spineElement = _child(root, 'spine');
    final spine = <ManifestItem>[
      for (final ref in _children(spineElement, 'itemref'))
        ?manifest[ref.getAttribute('idref')],
    ];
    if (spine.isEmpty) {
      throw FormatException('$opfPath has an empty or missing spine');
    }

    final metadataElement = _child(root, 'metadata');
    final metas = _children(metadataElement, 'meta').toList();
    final authors = [
      for (final e in _children(metadataElement, 'creator'))
        if (_text(e) case final text? when text.isNotEmpty) text,
    ];
    final metadata = BookMetadata(
      title: _firstText(metadataElement, 'title') ?? fallbackTitle,
      author: authors.isEmpty ? null : authors.join(', '),
      language: _firstText(metadataElement, 'language'),
    );

    return EpubPackage(
      path: opfPath,
      version: version,
      metadata: metadata,
      manifest: manifest,
      spine: spine,
      coverPath: _findCover(manifest, metas),
      ncxId: spineElement?.getAttribute('toc'),
    );
  }

  /// Entry name of the OPF inside the container.
  final String path;

  /// `version` attribute of `<package>`, e.g. `2.0` or `3.0`.
  final String version;

  /// Title, author(s) joined with ", ", and language of the book.
  final BookMetadata metadata;

  /// All manifest items by id.
  final Map<String, ManifestItem> manifest;

  /// Spine items in reading order; idrefs missing from the manifest are
  /// dropped. Includes items marked `linear="no"`.
  final List<ManifestItem> spine;

  /// Entry name of the cover image, when the OPF declares one.
  final String? coverPath;

  /// Id of the NCX item named by `<spine toc="...">` (EPUB 2), if any.
  final String? ncxId;

  /// The EPUB 3 navigation document (`properties="nav"`), if any.
  ManifestItem? get navItem {
    for (final item in manifest.values) {
      if (item.properties.contains('nav')) return item;
    }
    return null;
  }

  /// The NCX table of contents item, if the OPF has one.
  ManifestItem? get ncxItem {
    final byId = manifest[ncxId];
    if (byId != null) return byId;
    for (final item in manifest.values) {
      if (item.mediaType == 'application/x-dtbncx+xml') return item;
    }
    return null;
  }

  /// Whether the package declares EPUB 3 (or newer).
  bool get isEpub3 => version.startsWith('3') || version.startsWith('4');
}

String? _findCover(Map<String, ManifestItem> manifest, List<XmlElement> metas) {
  bool isImage(ManifestItem i) => i.mediaType.startsWith('image/');
  // EPUB 3: <item properties="cover-image">.
  for (final item in manifest.values) {
    if (item.properties.contains('cover-image') && isImage(item)) {
      return item.path;
    }
  }
  // EPUB 2: <meta name="cover" content="manifest-id"/>.
  for (final meta in metas) {
    if (meta.getAttribute('name') != 'cover') continue;
    final item = manifest[meta.getAttribute('content')];
    if (item != null && isImage(item)) return item.path;
  }
  // Common convention without metadata.
  for (final id in const ['cover', 'cover-image', 'coverimage']) {
    final item = manifest[id];
    if (item != null && isImage(item)) return item.path;
  }
  return null;
}

XmlElement? _child(XmlElement? parent, String local) {
  for (final e in _children(parent, local)) {
    return e;
  }
  return null;
}

Iterable<XmlElement> _children(XmlElement? parent, String local) =>
    parent == null
    ? const []
    : parent.childElements.where((e) => e.name.local == local);

String? _firstText(XmlElement? parent, String local) {
  for (final e in _children(parent, local)) {
    final text = _text(e);
    if (text != null && text.isNotEmpty) return text;
  }
  return null;
}

/// Text of [e] with whitespace runs collapsed to single spaces.
String? _text(XmlElement e) =>
    e.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
