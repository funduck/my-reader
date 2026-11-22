import 'dart:collection';

import 'package:sqlite3/sqlite3.dart';

/// Maps a word form to its base form.
abstract interface class Lemmatizer {
  /// Returns the lemma of [word], lower case; [pos] limits the candidates to
  /// one part of speech. Returns the normalized word if no lemma is known.
  String lemma(String word, {String? pos});
}

final RegExp _spaces = RegExp(r'\s+');

/// Normalizes [text] for pack lookups. Same rules as `normalize_key` in
/// `service/build/schema.py`: typographic apostrophes (U+2019, U+2018,
/// U+02BC, U+2032) become `'`, lower case, whitespace runs collapse to one
/// space, edges are trimmed. Hyphens and other punctuation stay.
String normalizeKey(String text) => text
    .replaceAll('’', "'")
    .replaceAll('‘', "'")
    .replaceAll('ʼ', "'")
    .replaceAll('′', "'")
    .toLowerCase()
    .replaceAll(_spaces, ' ')
    .trim();

/// Contractions whose stem is not a word on its own (`can't` -> `ca`).
const Map<String, String> _irregularStems = {
  "can't": 'can',
  "won't": 'will',
  "shan't": 'shall',
  "ain't": 'be',
};

/// Clitic suffixes stripped when the whole token is not in the table.
const List<String> _clitics = ["n't", "'s", "'re", "'ve", "'ll", "'d", "'m"];

/// [Lemmatizer] backed by the `forms` table of an `en-forms` pack.
///
/// The pack is opened read-only. A form with several candidates resolves to
/// the one with the lowest `rank` (the most frequent). The last
/// [cacheSize] distinct queries are cached in memory (least recently used
/// is evicted first).
///
/// A token that is not in the table is retried in a reduced form: a clitic
/// suffix is cut (`James's` -> `James`, `isn't` -> `is`, `can't` -> `can`),
/// and for a hyphenated token only its last part is lemmatized
/// (`ex-runners` -> `ex-runner`). The reduced form counts only if its base
/// is in the table; otherwise the normalized token itself is returned.
final class FormsLemmatizer implements Lemmatizer {
  /// Opens the pack at [path] read-only.
  factory open(String path, {int cacheSize = 1000}) =>
      FormsLemmatizer._(sqlite3.open(path, mode: OpenMode.readOnly), cacheSize);

  new _(this._db, this.cacheSize)
    : assert(cacheSize > 0, 'cacheSize must be positive'),
      _any = _db.prepare(
        'SELECT lemma FROM forms WHERE form = ? ORDER BY rank LIMIT 1',
      ),
      _byPos = _db.prepare(
        'SELECT lemma FROM forms WHERE form = ? AND pos = ? '
        'ORDER BY rank LIMIT 1',
      );

  /// Maximum number of cached queries.
  final int cacheSize;

  final Database _db;
  final PreparedStatement _any;
  final PreparedStatement _byPos;

  // Insertion order of a LinkedHashMap is the recency order.
  final LinkedHashMap<(String, String?), String> _cache = LinkedHashMap();
  var _closed = false;

  /// Number of queries currently cached.
  int get cachedCount => _cache.length;

  /// Whether a query for [word] (with [pos]) is in the cache.
  bool isCached(String word, {String? pos}) =>
      _cache.containsKey((normalizeKey(word), pos));

  @override
  String lemma(String word, {String? pos}) {
    if (_closed) throw StateError('FormsLemmatizer is closed');
    final key = normalizeKey(word);
    if (key.isEmpty) return key;
    final cacheKey = (key, pos);
    final hit = _cache.remove(cacheKey);
    if (hit != null) {
      _cache[cacheKey] = hit;
      return hit;
    }
    final result = _resolve(key, pos) ?? key;
    _cache[cacheKey] = result;
    if (_cache.length > cacheSize) _cache.remove(_cache.keys.first);
    return result;
  }

  String? _resolve(String key, String? pos) {
    final direct = _query(key, pos);
    if (direct != null) return direct;

    final irregular = _irregularStems[key];
    if (irregular != null) return _query(irregular, pos) ?? irregular;

    for (final clitic in _clitics) {
      if (key.length > clitic.length && key.endsWith(clitic)) {
        final stem = key.substring(0, key.length - clitic.length);
        final found = _query(stem, pos);
        if (found != null) return found;
      }
    }

    final dash = key.lastIndexOf('-');
    if (dash > 0 && dash < key.length - 1) {
      final last = _query(key.substring(dash + 1), pos);
      if (last != null) return '${key.substring(0, dash + 1)}$last';
    }
    return null;
  }

  String? _query(String form, String? pos) {
    final rows = pos == null ? _any.select([form]) : _byPos.select([form, pos]);
    return rows.isEmpty ? null : rows.first.columnAt(0) as String;
  }

  /// Releases the database. The lemmatizer cannot be used afterwards.
  void close() {
    if (_closed) return;
    _closed = true;
    _any.close();
    _byPos.close();
    _db.close();
  }
}
