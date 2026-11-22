import 'dart:typed_data';

import 'package:core/domain_books.dart';
import 'package:core/ports.dart';

/// An [OpenedBook] built from plain strings.
///
/// Chapter `i` has href `chapter<i+1>.xhtml`; its text becomes paragraphs,
/// split at blank lines. The table of contents has one entry per chapter.
class FakeOpenedBook implements OpenedBook {
  /// Creates a book with one chapter per string in [chapters].
  ///
  /// [titles] names the chapters (default `Chapter <n>`); [resources] maps
  /// href to bytes.
  new({
    required List<String> chapters,
    List<String>? titles,
    Map<String, Uint8List> resources = const {},
  }) : _texts = List.of(chapters),
       _resources = Map.of(resources),
       spine = List.unmodifiable([
         for (var i = 0; i < chapters.length; i++)
           ChapterRef(href: 'chapter${i + 1}.xhtml', index: i),
       ]),
       toc = List.unmodifiable([
         for (var i = 0; i < chapters.length; i++)
           TocEntry(
             title: titles != null ? titles[i] : 'Chapter ${i + 1}',
             chapter: ChapterRef(href: 'chapter${i + 1}.xhtml', index: i),
           ),
       ]);

  final List<String> _texts;
  final Map<String, Uint8List> _resources;
  bool _closed = false;

  @override
  final List<TocEntry> toc;

  @override
  final List<ChapterRef> spine;

  /// Whether [close] has been called.
  bool get isClosed => _closed;

  void _ensureOpen() {
    if (_closed) throw StateError('Book is closed');
  }

  @override
  Future<ContentDocument> chapter(ChapterRef ref) async {
    _ensureOpen();
    final known =
        ref.index >= 0 &&
        ref.index < spine.length &&
        spine[ref.index].href == ref.href;
    if (!known) throw ArgumentError.value(ref, 'ref', 'not in spine');
    return ContentDocument([
      for (final p in _texts[ref.index].split(RegExp(r'\n\s*\n')))
        if (p.trim().isNotEmpty) ParagraphBlock([TextInline(p.trim())]),
    ]);
  }

  @override
  Future<Uint8List> resource(String href) async {
    _ensureOpen();
    final bytes = _resources[href];
    if (bytes == null) throw ArgumentError.value(href, 'href', 'no resource');
    return bytes;
  }

  @override
  Future<void> close() async => _closed = true;
}
