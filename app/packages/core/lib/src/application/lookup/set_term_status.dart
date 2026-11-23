import '../../domain/lookup/ids.dart';
import '../../domain/lookup/term.dart';
import '../../domain/lookup/term_status.dart';
import '../../ports/id_generator.dart';
import '../../ports/level_dictionary.dart';
import '../../ports/repositories.dart';

/// The scenario "mark a word as known / learning / ignored" (T-5, S-6).
///
/// Works on a term key, the same one `LookupSelection` writes into
/// `Term.normalized` (see `termKey`). A word that was never looked up (marked
/// from the cheat sheet) gets a term with no lookups and no events, so the
/// mark survives; its level comes from the [LevelDictionary]. For an existing
/// term only the status changes, and only if it differs.
class SetTermStatus {
  /// Creates the scenario.
  new({required this._terms, required this._levels, required this._ids});

  final TermRepository _terms;
  final LevelDictionary _levels;
  final IdGenerator _ids;

  /// Sets [status] on the term [normalized] of [language] and returns it.
  ///
  /// Writes nothing when the term already has [status].
  Future<Term> call(
    String normalized,
    TermStatus status, {
    String language = 'en',
  }) async {
    final existing = await _terms.find(normalized, language);
    if (existing == null) {
      final term = Term(
        id: TermId(_ids.newId()),
        normalized: normalized,
        language: language,
        lookupCount: 0,
        eventIds: const [],
        status: status,
        level: _levels.levelOf(normalized).level,
      );
      await _terms.save(term);
      return term;
    }
    if (existing.status == status) return existing;
    final term = existing.copyWith(status: status);
    await _terms.save(term);
    return term;
  }
}
