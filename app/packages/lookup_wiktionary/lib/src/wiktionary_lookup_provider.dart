import 'dart:async';

import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:sqlite3/sqlite3.dart';

import 'normalize_key.dart';

/// Returns lemma candidates for a surface form, best first; may be empty.
typedef LemmaCandidates = List<String> Function(String text);

/// Offline English definitions from the `en-en` pack (Wiktionary, CC BY-SA).
///
/// Serves [LookupMode.enEn] only. The pack file is found through the
/// [PackStore]; it is opened read-only on the first lookup and kept open until
/// [close]. The provider does not lemmatize: [lemmas] is an optional hook, and
/// without it the query text is tried as is. Lemma candidates are tried first,
/// then the normalized query text.
class WiktionaryLookupProvider implements LookupProvider {
  /// Creates a provider reading pack [packId] from [packStore].
  new({required this._packStore, this.lemmas, this._packId = defaultPackId});

  /// Pack id of the Wiktionary en-en pack.
  static const String defaultPackId = 'en-en';

  /// Id stored in history.
  static const ProviderId providerId = ProviderId('wiktionary.en-en');

  static const String _sql = '''
SELECT e.id, e.pos, e.ipa, s.id, s.gloss, x.text
FROM entries e
JOIN senses s ON s.entry_id = e.id
LEFT JOIN examples x ON x.sense_id = s.id
WHERE e.key = ?
ORDER BY e.rank, s.idx, x.idx''';

  final PackStore _packStore;
  final String _packId;

  /// Optional lemma source for the query text.
  final LemmaCandidates? lemmas;

  String? _openPath;
  Database? _db;
  PreparedStatement? _statement;

  @override
  ProviderId get id => providerId;

  @override
  ProviderInfo get info => const ProviderInfo(
    name: 'Wiktionary (offline)',
    isOnline: false,
    modes: {LookupMode.enEn},
  );

  @override
  bool supports(LookupMode mode) => mode == LookupMode.enEn;

  @override
  Future<LookupResult> lookup(LookupQuery query, {CancelToken? cancel}) async {
    cancel?.throwIfCancelled();
    if (!supports(query.mode)) {
      throw ProviderUnavailable('Wiktionary pack has no ${query.mode.name}');
    }
    final path = await _packStore.pathOf(_packId);
    cancel?.throwIfCancelled();
    if (path == null) {
      throw ProviderUnavailable('Pack "$_packId" is not installed');
    }
    final statement = _statementFor(path);
    for (final key in _candidates(query.text)) {
      final result = _read(statement, key);
      if (result != null) return result;
    }
    throw LookupNotFound('No entry for "${query.text}"');
  }

  /// Closes the pack file; the next lookup reopens it.
  void close() {
    _statement?.close();
    _db?.close();
    _statement = null;
    _db = null;
    _openPath = null;
  }

  List<String> _candidates(String text) {
    final keys = <String>[];
    for (final lemma in lemmas?.call(text) ?? const <String>[]) {
      final key = normalizeKey(lemma);
      if (key.isNotEmpty && !keys.contains(key)) keys.add(key);
    }
    final own = normalizeKey(text);
    if (own.isNotEmpty && !keys.contains(own)) keys.add(own);
    return keys;
  }

  PreparedStatement _statementFor(String path) {
    final current = _statement;
    if (current != null && _openPath == path) return current;
    close();
    try {
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      _db = db;
      _openPath = path;
      return _statement = db.prepare(_sql);
    } on SqliteException catch (e) {
      close();
      throw ProviderUnavailable('Cannot open pack "$_packId": ${e.message}');
    }
  }

  LookupResult? _read(PreparedStatement statement, String key) {
    final ResultSet rows;
    try {
      rows = statement.select([key]);
    } on SqliteException catch (e) {
      throw ProviderUnavailable('Pack "$_packId" is unreadable: ${e.message}');
    }
    if (rows.isEmpty) return null;
    final senses = <Sense>[];
    String? ipa;
    int? senseId;
    String? gloss;
    String? pos;
    var examples = <String>[];
    void flush() {
      final text = gloss;
      if (text != null) {
        senses.add(Sense(text: text, partOfSpeech: pos, examples: examples));
      }
    }

    for (final row in rows) {
      final rowIpa = row.columnAt(2) as String?;
      if (ipa == null && rowIpa != null && rowIpa.isNotEmpty) ipa = rowIpa;
      final rowSense = row.columnAt(3) as int;
      if (rowSense != senseId) {
        flush();
        senseId = rowSense;
        gloss = row.columnAt(4) as String;
        pos = row.columnAt(1) as String;
        examples = <String>[];
      }
      final example = row.columnAt(5) as String?;
      if (example != null) examples.add(example);
    }
    flush();
    return LookupResult(provider: id, senses: senses, transcription: ipa);
  }
}
