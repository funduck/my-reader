/// Path helpers for addresses inside an EPUB container (ZIP entry names).
library;

import 'dart:convert';

/// Normalizes [href] into a ZIP entry name.
///
/// Drops `#fragment` and `?query`, percent-decodes (keeping the raw text when
/// it is not valid percent-encoding), resolves `.` and `..` segments and
/// leading slashes. Returns null when `..` climbs above the container root.
String? normalizeEntryPath(String href) {
  var path = href;
  final cut = path.indexOf(RegExp('[#?]'));
  if (cut >= 0) path = path.substring(0, cut);
  path = _percentDecode(path);
  final out = <String>[];
  for (final segment in path.replaceAll(r'\', '/').split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (out.isEmpty) return null;
      out.removeLast();
    } else {
      out.add(segment);
    }
  }
  return out.join('/');
}

/// Decodes valid `%XX` sequences as UTF-8; a stray `%` stays a literal `%`.
String _percentDecode(String s) {
  return s.replaceAllMapped(RegExp('(?:%[0-9A-Fa-f]{2})+'), (m) {
    final run = m[0]!;
    final bytes = [
      for (var i = 0; i < run.length; i += 3)
        int.parse(run.substring(i + 1, i + 3), radix: 16),
    ];
    return utf8.decode(bytes, allowMalformed: true);
  });
}

/// Resolves [href] (as written in a document located at [basePath]) to a ZIP
/// entry name. Returns null for hrefs that leave the container or are external
/// (`http:`, `mailto:` and other schemes).
String? resolveEntryPath(String basePath, String href) {
  if (RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(href)) return null;
  if (href.startsWith('/')) return normalizeEntryPath(href);
  final slash = basePath.lastIndexOf('/');
  final dir = slash < 0 ? '' : basePath.substring(0, slash + 1);
  return normalizeEntryPath('$dir$href');
}
