import 'package:core/domain_books.dart';
import 'package:xml/xml.dart';

import '../epub_archive.dart';
import '../epub_package.dart';
import '../epub_path.dart';

/// Builds the table of contents of the book described by [package].
///
/// Order of sources: the EPUB 3 navigation document, then the EPUB 2 NCX,
/// then one entry per spine item. A source that is missing, malformed or
/// yields no usable entries is skipped.
///
/// Every [TocEntry.chapter] has `href` = container entry name of the target
/// file, followed by `#fragment` when the source link had one, and `index` =
/// position of that file in the spine. Entries whose target is not in the
/// spine (external links, files outside reading order) are dropped; their
/// children move up one level.
List<TocEntry> parseToc(EpubArchive archive, EpubPackage package) {
  final spineIndex = <String, int>{};
  for (final (i, item) in package.spine.indexed) {
    spineIndex.putIfAbsent(item.path, () => i);
  }
  final nav = package.navItem;
  if (nav != null) {
    final entries = _tryParse(
      () => _fromNav(archive, nav.path, spineIndex),
      archive,
      nav.path,
    );
    if (entries.isNotEmpty) return entries;
  }
  final ncx = package.ncxItem;
  if (ncx != null) {
    final entries = _tryParse(
      () => _fromNcx(archive, ncx.path, spineIndex),
      archive,
      ncx.path,
    );
    if (entries.isNotEmpty) return entries;
  }
  return _fromSpine(archive, package);
}

List<TocEntry> _tryParse(
  List<TocEntry> Function() parse,
  EpubArchive archive,
  String path,
) {
  if (!archive.contains(path)) return const [];
  try {
    return parse();
  } on FormatException {
    return const [];
  }
}

/// A link as written in a nav or NCX document, before resolving.
final class _RawEntry {
  const new(this.title, this.href, this.children);

  final String title;
  final String? href;
  final List<_RawEntry> children;
}

List<TocEntry> _resolve(
  List<_RawEntry> raw,
  String basePath,
  Map<String, int> spineIndex,
) {
  final result = <TocEntry>[];
  for (final entry in raw) {
    final children = _resolve(entry.children, basePath, spineIndex);
    final href = entry.href;
    final target = href == null ? null : _target(basePath, href, spineIndex);
    final title = entry.title;
    if (title.isEmpty) {
      result.addAll(children);
    } else if (target != null) {
      result.add(TocEntry(title: title, chapter: target, children: children));
    } else if (children.isNotEmpty) {
      // Group heading without a link of its own points at its first child.
      result.add(
        TocEntry(
          title: title,
          chapter: children.first.chapter,
          children: children,
        ),
      );
    }
  }
  return result;
}

ChapterRef? _target(String basePath, String href, Map<String, int> spineIndex) {
  final path = resolveEntryPath(basePath, href);
  if (path == null) return null;
  final index = spineIndex[path];
  if (index == null) return null;
  final hash = href.indexOf('#');
  final fragment = hash < 0 ? '' : href.substring(hash + 1);
  return ChapterRef(
    href: fragment.isEmpty ? path : '$path#$fragment',
    index: index,
  );
}

String _collapse(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

Iterable<XmlElement> _kids(XmlElement e, String local) =>
    e.childElements.where((c) => c.name.local == local);

// --- EPUB 3 nav ---------------------------------------------------------

List<TocEntry> _fromNav(
  EpubArchive archive,
  String path,
  Map<String, int> spineIndex,
) {
  final root = archive.readXml(path).rootElement;
  for (final nav in root.descendantElements) {
    if (nav.name.local != 'nav' || !_isTocNav(nav)) continue;
    final list = _kids(nav, 'ol').firstOrNull;
    if (list == null) continue;
    return _resolve(_navList(list), path, spineIndex);
  }
  return const [];
}

bool _isTocNav(XmlElement nav) {
  for (final attribute in nav.attributes) {
    if (attribute.name.local != 'type') continue;
    if (_collapse(attribute.value).split(' ').contains('toc')) return true;
  }
  return false;
}

List<_RawEntry> _navList(XmlElement ol) => [
  for (final li in _kids(ol, 'li')) _navItem(li),
];

_RawEntry _navItem(XmlElement li) {
  final link = _kids(li, 'a').firstOrNull;
  final label = link ?? _kids(li, 'span').firstOrNull;
  final nested = _kids(li, 'ol').firstOrNull;
  return _RawEntry(
    label == null ? '' : _collapse(label.innerText),
    link?.getAttribute('href'),
    nested == null ? const [] : _navList(nested),
  );
}

// --- EPUB 2 NCX ---------------------------------------------------------

List<TocEntry> _fromNcx(
  EpubArchive archive,
  String path,
  Map<String, int> spineIndex,
) {
  final root = archive.readXml(path).rootElement;
  final map = _kids(root, 'navMap').firstOrNull;
  if (map == null) return const [];
  return _resolve(_ncxPoints(map), path, spineIndex);
}

List<_RawEntry> _ncxPoints(XmlElement parent) => [
  for (final point in _kids(parent, 'navPoint'))
    _RawEntry(
      _collapse(_kids(point, 'navLabel').firstOrNull?.innerText ?? ''),
      _kids(point, 'content').firstOrNull?.getAttribute('src'),
      _ncxPoints(point),
    ),
];

// --- No table of contents -----------------------------------------------

List<TocEntry> _fromSpine(EpubArchive archive, EpubPackage package) => [
  for (final (i, item) in package.spine.indexed)
    TocEntry(
      title: _headingTitle(archive, item.path) ?? _baseName(item.path),
      chapter: ChapterRef(href: item.path, index: i),
    ),
];

String? _headingTitle(EpubArchive archive, String path) {
  if (!archive.contains(path)) return null;
  final String source;
  try {
    source = archive.readText(path);
  } on FormatException {
    return null;
  }
  try {
    final root = XmlDocument.parse(source).rootElement;
    for (final e in root.descendantElements) {
      if (!const {'h1', 'h2', 'h3'}.contains(e.name.local)) continue;
      final text = _collapse(e.innerText);
      if (text.isNotEmpty) return text;
    }
    return null;
  } on XmlException {
    // HTML entities such as &nbsp; make XHTML malformed XML: scan the text.
    final matches = RegExp(
      '<h[1-3][^>]*>(.*?)</h[1-3]>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(source);
    for (final m in matches) {
      final text = _collapse(
        m[1]!.replaceAll(RegExp('<[^>]*>'), '').replaceAll('&nbsp;', ' '),
      );
      if (text.isNotEmpty) return text;
    }
    return null;
  }
}

String _baseName(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}
