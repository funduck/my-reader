import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:sqlite3/sqlite3.dart';

/// [LevelDictionary] over the `en-levels` pack (`levels` table).
///
/// Without a pack every word is [CefrLevel.unknown].
final class CefrLevelDictionary implements LevelDictionary {
  new _(this._db) {
    _statement = _db?.prepare(
      'SELECT pos, cefr, zipf, estimated FROM levels WHERE lemma = ?',
    );
  }

  /// A dictionary without data: always answers [CefrLevel.unknown].
  new empty() : this._(null);

  /// Opens the pack file at [path] read-only.
  factory fromPath(String path) =>
      CefrLevelDictionary._(sqlite3.open(path, mode: OpenMode.readOnly));

  /// Opens the installed `en-levels` pack from [store].
  ///
  /// If the pack is not installed, returns an empty dictionary.
  static Future<CefrLevelDictionary> open(PackStore store) async {
    final path = await store.pathOf('en-levels');
    if (path == null) return CefrLevelDictionary.empty();
    return CefrLevelDictionary.fromPath(path);
  }

  final Database? _db;
  PreparedStatement? _statement;

  @override
  WordLevel levelOf(String lemma, {String? pos}) {
    final statement = _statement;
    if (statement == null) return const WordLevel(CefrLevel.unknown);
    final rows = statement.select([normalizeKey(lemma)]);
    final variants = [
      for (final row in rows)
        (
          pos: row.columnAt(0) as String,
          level: CefrLevel.fromJson(row.columnAt(1)),
          zipf: (row.columnAt(2) as num?)?.toDouble(),
          estimated: row.columnAt(3) == 1,
        ),
    ];
    if (variants.isEmpty) return const WordLevel(CefrLevel.unknown);
    final wanted = pos == null ? null : normalizeKey(pos);
    final narrowed = wanted == null
        ? variants
        : variants.where((v) => v.pos == wanted || v.pos == 'any').toList();
    // A part of speech the pack does not know falls back to all variants.
    final pool = narrowed.isEmpty ? variants : narrowed;
    var best = pool.first;
    for (final v in pool.skip(1)) {
      if (_isBetter(v.level, best.level)) best = v;
    }
    return WordLevel(best.level, estimated: best.estimated, zipf: best.zipf);
  }

  /// Easiest known level wins; any known level beats unknown.
  static bool _isBetter(CefrLevel candidate, CefrLevel current) {
    if (!candidate.isKnown) return false;
    if (!current.isKnown) return true;
    return candidate.index < current.index;
  }

  /// Releases the database; the dictionary answers unknown afterwards.
  void close() {
    _statement?.close();
    _statement = null;
    _db?.close();
  }

  /// Normalizes [text] like `normalize_key` in the service.
  static String normalizeKey(String text) => text
      .replaceAll(RegExp('[’‘ʼ′]'), "'")
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
