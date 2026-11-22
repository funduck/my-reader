import 'package:core/domain_books.dart';

/// Where a chapter begins: a spine file and a top-level block inside it.
final class _Start {
  const new(this.file, this.block, this.href);

  final int file;
  final int block;
  final String href;

  bool atOrBefore(int otherFile, int otherBlock) =>
      file < otherFile || (file == otherFile && block <= otherBlock);
}

/// Cuts the spine files of a book into chapters following its table of
/// contents.
///
/// Chapter starts are the top-level [TocEntry] targets. A target with a
/// `#fragment` begins at the top-level block that holds the element with that
/// id (see `ChapterContent.anchors`); a target without a fragment, or with an
/// id that cannot be found, begins at the first block of its file. Starts are
/// ordered by position in the book; entries at the same position as an earlier
/// one are dropped. Text before the first start (cover, title page) becomes a
/// leading chapter that begins at the first spine file.
///
/// A chapter runs from its start to the next one, across as many spine files
/// as lie between them.
final class ChapterPlan {
  new _(this._spinePaths, this._starts);

  /// Plans the chapters of a book.
  ///
  /// [spinePaths] are entry names of the spine files, [toc] the table of
  /// contents whose `ChapterRef.index` is a spine file position, and
  /// [anchorsOf] returns the anchors of a spine file, or null when the file
  /// cannot be converted.
  factory build({
    required List<String> spinePaths,
    required List<TocEntry> toc,
    required Map<String, int>? Function(String path) anchorsOf,
  }) {
    if (spinePaths.isEmpty) return ChapterPlan._(spinePaths, const []);
    final found = <_Start>[];
    for (final entry in toc) {
      final ref = entry.chapter;
      if (ref.index < 0 || ref.index >= spinePaths.length) continue;
      final path = spinePaths[ref.index];
      final hasFragment = ref.href.length > path.length + 1;
      final fragment = hasFragment ? ref.href.substring(path.length + 1) : '';
      final block = fragment.isEmpty ? 0 : (anchorsOf(path)?[fragment] ?? 0);
      found.add(_Start(ref.index, block, ref.href));
    }
    // List.sort is not stable: keep the table-of-contents order on ties.
    final order = [for (var i = 0; i < found.length; i++) i]
      ..sort((a, b) {
        final byFile = found[a].file.compareTo(found[b].file);
        if (byFile != 0) return byFile;
        final byBlock = found[a].block.compareTo(found[b].block);
        return byBlock != 0 ? byBlock : a.compareTo(b);
      });
    final starts = <_Start>[];
    for (final i in order) {
      final s = found[i];
      final last = starts.lastOrNull;
      if (last != null && last.file == s.file && last.block == s.block) {
        continue;
      }
      starts.add(s);
    }
    final first = starts.firstOrNull;
    if (first == null || first.file != 0 || first.block != 0) {
      starts.insert(0, _Start(0, 0, spinePaths.first));
    }
    return ChapterPlan._(spinePaths, List.unmodifiable(starts));
  }

  final List<String> _spinePaths;
  final List<_Start> _starts;

  /// Number of chapters.
  int get length => _starts.length;

  /// Chapters in reading order; `href` is the target of the table-of-contents
  /// entry (container entry name, plus `#fragment` when it had one), `index`
  /// the chapter position.
  late final List<ChapterRef> refs = List.unmodifiable([
    for (final (i, s) in _starts.indexed) ChapterRef(href: s.href, index: i),
  ]);

  /// Index of the chapter whose start href is exactly [href], or -1.
  int indexOfHref(String href) => _starts.indexWhere((s) => s.href == href);

  /// Index of the chapter that contains the place at top-level block [block]
  /// of spine file [file].
  int indexAt(int file, int block) {
    for (var i = _starts.length - 1; i >= 0; i--) {
      if (_starts[i].atOrBefore(file, block)) return i;
    }
    return 0;
  }

  /// Slices of the spine files that make up chapter [index], in order:
  /// `(file path, first block, end block exclusive or null for to the end)`.
  List<(String, int, int?)> parts(int index) {
    final start = _starts[index];
    final next = index + 1 < _starts.length ? _starts[index + 1] : null;
    final endFile = next?.file;
    final endBlock = next?.block ?? 0;
    final lastFile = endFile ?? _spinePaths.length - 1;
    return [
      for (var f = start.file; f <= lastFile; f++)
        if (f != endFile || endBlock > 0)
          (
            _spinePaths[f],
            f == start.file ? start.block : 0,
            f == endFile ? endBlock : null,
          ),
    ];
  }
}
