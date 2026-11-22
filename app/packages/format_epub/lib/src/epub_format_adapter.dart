import 'dart:io';
import 'dart:typed_data';

import 'package:core/domain_books.dart';
import 'package:core/ports.dart';

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
/// [toc] comes from nav.xhtml, toc.ncx or the spine (see `parseToc`);
/// chapter parsing is added by a later task and [chapter] throws
/// [UnsupportedError] until then.
final class EpubBook implements OpenedBook {
  new _(this._archive, this.package);

  final EpubArchive _archive;
  bool _closed = false;

  /// Parsed OPF: metadata, manifest and spine.
  final EpubPackage package;

  @override
  late final List<TocEntry> toc = List.unmodifiable(
    parseToc(_archive, package),
  );

  /// Spine in reading order; `href` is the container entry name of the
  /// chapter file (e.g. `OEBPS/text/ch1.xhtml`), `index` its spine position.
  @override
  late final List<ChapterRef> spine = List.unmodifiable([
    for (final (i, item) in package.spine.indexed)
      ChapterRef(href: item.path, index: i),
  ]);

  @override
  Future<ContentDocument> chapter(ChapterRef ref) =>
      throw UnsupportedError('Chapter parsing is not implemented yet');

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
