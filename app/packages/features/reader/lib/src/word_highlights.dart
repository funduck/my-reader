import 'dart:async';

import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('WordHighlightSource');

/// The lemma sets of the word highlights of one book (T-119).
@immutable
final class WordHighlightSets {
  /// Creates the sets.
  const new({this.cheatSheet = const {}, this.lookedUp = const {}});

  /// Lemmas of the last cheat sheet of the book.
  final Set<String> cheatSheet;

  /// Lemmas of the words looked up after that cheat sheet (all lookups of the
  /// book while there is no cheat sheet).
  final Set<String> lookedUp;

  @override
  bool operator ==(Object other) =>
      other is WordHighlightSets &&
      setEquals(other.cheatSheet, cheatSheet) &&
      setEquals(other.lookedUp, lookedUp);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(cheatSheet),
    Object.hashAllUnordered(lookedUp),
  );
}

/// Watches the cheat sheet log, the lookup journal and the terms, and tells
/// the owner the lemma sets of the `cheatSheet` and `lookedUp` highlights of
/// one book whenever they change.
///
/// Looked-up lemmas use the key of `Term.normalized` ([termKey]), so they
/// match the lemmas the engine looks for; cheat sheet lemmas are already
/// lemmas and are only lower-cased. A phrase (more than one word) is never a
/// lemma. Terms marked as known are left out of both sets. Nothing is
/// reported until the first value of every source has arrived, so a late
/// cheat sheet does not flash its words as "looked up".
class WordHighlightSource {
  /// Creates the source; call [start] to begin watching.
  new({
    required this.book,
    required this._cheatSheets,
    required this._journal,
    required this._terms,
    required this._analyzer,
    required this.onChanged,
    this.language = 'en',
  });

  /// The book whose words are watched.
  final BookId book;

  /// Language of the terms whose "known" mark hides a word.
  final String language;

  /// Called with the new sets after every change.
  final void Function(WordHighlightSets sets) onChanged;

  final CheatSheetLog _cheatSheets;
  final LookupJournal _journal;
  final TermRepository _terms;
  final TextAnalyzer _analyzer;

  StreamSubscription<CheatSheetSnapshot?>? _sheetSub;
  StreamSubscription<List<LookupEvent>>? _journalSub;
  StreamSubscription<List<Term>>? _termsSub;

  bool _closed = false;
  bool _sheetSeen = false;
  bool _termsSeen = false;
  bool _eventsSeen = false;
  CheatSheetSnapshot? _snapshot;
  DateTime? _from;
  Set<String> _known = const {};
  List<LookupEvent> _events = const [];
  WordHighlightSets? _last;

  /// Starts watching.
  void start() {
    _sheetSub = _cheatSheets
        .watch(book)
        .listen(
          _onSnapshot,
          onError: (Object e, StackTrace s) =>
              _log.warning('Watching the cheat sheet log failed', e, s),
        );
    _termsSub = _terms
        .watchAll(status: TermStatus.known)
        .listen(
          _onTerms,
          onError: (Object e, StackTrace s) =>
              _log.warning('Watching the known terms failed', e, s),
        );
  }

  /// Stops watching; `onChanged` is not called afterwards.
  Future<void> dispose() async {
    _closed = true;
    await _sheetSub?.cancel();
    await _journalSub?.cancel();
    await _termsSub?.cancel();
  }

  void _onSnapshot(CheatSheetSnapshot? snapshot) {
    if (_closed) return;
    final firstTime = !_sheetSeen;
    _sheetSeen = true;
    _snapshot = snapshot;
    final from = snapshot?.shownAt;
    if (firstTime || from != _from) {
      _from = from;
      _watchJournal(from);
    }
    _emit();
  }

  void _watchJournal(DateTime? from) {
    unawaited(_journalSub?.cancel());
    // The lookups of the old window do not count for the new one.
    _eventsSeen = false;
    _events = const [];
    _journalSub = _journal.watch(LookupFilter(book: book, from: from)).listen(
      (events) {
        if (_closed) return;
        _eventsSeen = true;
        _events = events;
        _emit();
      },
      onError: (Object e, StackTrace s) =>
          _log.warning('Watching the lookup journal failed', e, s),
    );
  }

  void _onTerms(List<Term> terms) {
    if (_closed) return;
    _termsSeen = true;
    _known = {
      for (final term in terms)
        if (term.language == language) term.normalized,
    };
    _emit();
  }

  bool _isWord(String text) => _analyzer.tokens(text).length == 1;

  void _emit() {
    if (!(_sheetSeen && _termsSeen && _eventsSeen)) return;
    final sheet = <String>{};
    for (final text in _snapshot?.lemmas ?? const <String>[]) {
      final lemma = text.toLowerCase();
      if (_isWord(text) && !_known.contains(lemma)) sheet.add(lemma);
    }
    final looked = <String>{};
    for (final event in _events) {
      final text = event.query.text;
      if (!_isWord(text)) continue;
      final lemma = termKey(_analyzer, text);
      if (!_known.contains(lemma)) looked.add(lemma);
    }
    final sets = WordHighlightSets(cheatSheet: sheet, lookedUp: looked);
    if (sets == _last) return;
    _last = sets;
    onChanged(sets);
  }
}
