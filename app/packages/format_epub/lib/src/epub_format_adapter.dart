import 'dart:io';
import 'dart:typed_data';

import 'package:core/domain_books.dart';
import 'package:core/ports.dart';

import 'chapters.dart';
import 'content/xhtml_to_content.dart';
import 'epub_archive.dart';
import 'epub_package.dart';
import 'epub_path.dart';
import 'toc/toc_parser.dart';

/// [BookFormatAdapter] for EPUB 2 and EPUB 3.
final class EpubFormatAdapter implements BookFormatAdapter {
  /// Creates the adapter.
  const new();

  @override
  Set<BookFormat> get formats => const {BookFormat.epub};

  @override
  Future<bool> canOpen(String path) async {
    try {
      final (archive, opfPath) = await _readContainer(path);
      return archive.contains(opfPath);
    } on FormatException {
      return false;
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<BookMetadata> readMetadata(String path) async =>
      (await _readPackage(path)).$2.metadata;

  /// Reads the cover image of the book at [path]; null when it has none.
  Future<Uint8List?> readCover(String path) async {
    final (archive, package) = await _readPackage(path);
    final cover = package.coverPath;
    return cover != null && archive.contains(cover)
        ? archive.read(cover)
        : null;
  }

  @override
  Future<EpubBook> open(String path) async {
    final (archive, package) = await _readPackage(path);
    return EpubBook._(archive, package);
  }

  Future<(EpubArchive, String)> _readContainer(String path) async {
    final Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } on FileSystemException catch (e) {
      throw FormatException('Cannot read $path: ${e.message}');
    }
    final archive = EpubArchive.fromBytes(bytes);
    return (archive, archive.findPackagePath());
  }

  Future<(EpubArchive, EpubPackage)> _readPackage(String path) async {
    final (archive, opfPath) = await _readContainer(path);
    final package = EpubPackage.parse(
      archive,
      opfPath,
      fallbackTitle: _baseName(path),
    );
    return (archive, package);
  }
}

String _baseName(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/// An opened EPUB: package structure plus access to its entries.
///
/// Chapters follow the table of contents, not the files: see [ChapterPlan].
/// Several chapters may share one file, and one chapter may span several
/// files. [spine] lists the chapters, [toc] the table of contents whose
/// `ChapterRef.index` is a chapter position (a nested entry points to the
/// chapter that contains it), and [chapter] returns exactly one chapter.
final class EpubBook implements OpenedBook {
  new _(this._archive, this.package);

  final EpubArchive _archive;
  bool _closed = false;
  final Map<String, ChapterContent?> _converted = {};

  /// Parsed OPF: metadata, manifest and spine.
  final EpubPackage package;

  late final List<TocEntry> _fileToc = List.unmodifiable(
    parseToc(_archive, package),
  );

  late final List<String> _filePaths = [for (final i in package.spine) i.path];

  late final Map<String, int> _fileIndex = {
    for (final (i, path) in _filePaths.indexed) path: i,
  };

  late final ChapterPlan _plan = ChapterPlan.build(
    spinePaths: _filePaths,
    toc: _fileToc,
    anchorsOf: (path) => _convertedOrNull(path)?.anchors,
  );

  /// Table of contents from nav.xhtml, toc.ncx or the spine (see
  /// `parseToc`). `href` is the container entry name of the target file with
  /// `#fragment` when the source link had one; `index` is the position of
  /// the chapter (see [spine]) that contains the target.
  @override
  late final List<TocEntry> toc = List.unmodifiable(_chapterToc(_fileToc));

  /// Chapters in reading order, one per top-level table-of-contents entry
  /// (plus a leading one for text before the first entry, if any).
  ///
  /// `href` is the target of the entry: container entry name, followed by
  /// `#fragment` when the entry had one; `index` is the position in this list.
  @override
  late final List<ChapterRef> spine = _plan.refs;

  /// Parses the chapter [ref] points to: exactly one chapter.
  ///
  /// [ref] is found by `href`: a chapter start as listed in [spine] or [toc]
  /// selects that chapter; any other place in the book (a file, a file with
  /// `#fragment`, a nested table-of-contents entry) selects the chapter that
  /// contains it. `index` is ignored. Throws [FormatException] when the
  /// target is not in the spine or the XHTML is malformed.
  @override
  Future<ContentDocument> chapter(ChapterRef ref) async {
    _checkOpen();
    final index = _chapterIndexOf(ref.href);
    final blocks = <Block>[];
    for (final (path, from, to) in _plan.parts(index)) {
      final all = _convert(path).document.blocks;
      final end = to ?? all.length;
      if (from < end) blocks.addAll(all.sublist(from, end));
    }
    return ContentDocument(blocks);
  }

  int _chapterIndexOf(String href) {
    final exact = _plan.indexOfHref(href);
    if (exact >= 0) return exact;
    final path = normalizeEntryPath(href);
    final file = path == null ? null : _fileIndex[path];
    if (file == null) {
      throw FormatException('No such chapter in the EPUB: $href');
    }
    final hash = href.indexOf('#');
    final fragment = hash < 0 ? '' : href.substring(hash + 1);
    final block = fragment.isEmpty
        ? 0
        : (_convertedOrNull(path!)?.anchors[fragment] ?? 0);
    return _plan.indexAt(file, block);
  }

  List<TocEntry> _chapterToc(List<TocEntry> entries) => [
    for (final e in entries)
      e.copyWith(
        chapter: e.chapter.copyWith(index: _chapterIndexOfEntry(e.chapter)),
        children: _chapterToc(e.children),
      ),
  ];

  int _chapterIndexOfEntry(ChapterRef ref) {
    final exact = _plan.indexOfHref(ref.href);
    if (exact >= 0) return exact;
    final path = _filePaths[ref.index];
    final hasFragment = ref.href.length > path.length + 1;
    final block = hasFragment
        ? (_convertedOrNull(path)
                  ?.anchors[ref.href.substring(path.length + 1)] ??
              0)
        : 0;
    return _plan.indexAt(ref.index, block);
  }

  ChapterContent _convert(String path) {
    final cached = _converted[path];
    if (cached != null) return cached;
    final content = convertXhtml(_archive.readText(path), path: path);
    return _converted[path] = content;
  }

  /// Like [_convert], but null when the file is unreadable or malformed.
  ChapterContent? _convertedOrNull(String path) {
    if (_converted.containsKey(path)) return _converted[path];
    try {
      return _convert(path);
    } on FormatException {
      return _converted[path] = null;
    }
  }

  /// Returns the raw bytes of the entry at [href].
  ///
  /// [href] is a container entry name as in [ChapterRef.href] or
  /// [ManifestItem.path]; percent-encoding, `./`, `../` and `#fragment` are
  /// tolerated. Throws [FormatException] when no such entry exists.
  @override
  Future<Uint8List> resource(String href) async {
    _checkOpen();
    final path = normalizeEntryPath(href);
    if (path == null || !_archive.contains(path)) {
      throw FormatException('No such resource in the EPUB: $href');
    }
    return _archive.read(path);
  }

  /// Raw bytes of the cover image, or null when the book declares none.
  Future<Uint8List?> cover() async {
    _checkOpen();
    final cover = package.coverPath;
    return cover != null && _archive.contains(cover)
        ? _archive.read(cover)
        : null;
  }

  /// Reads the entry [href] as UTF-8 text (for XHTML, NCX and nav documents).
  Future<String> resourceText(String href) async {
    _checkOpen();
    final path = normalizeEntryPath(href);
    if (path == null || !_archive.contains(path)) {
      throw FormatException('No such resource in the EPUB: $href');
    }
    return _archive.readText(path);
  }

  @override
  Future<void> close() async => _closed = true;

  void _checkOpen() {
    if (_closed) throw StateError('The book is closed');
  }
}
