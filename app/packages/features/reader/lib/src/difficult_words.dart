import 'dart:async';

import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('DifficultWords');

/// Keeps the set of difficult words of the open chapter up to date (T-117).
///
/// The words are lemmas for `ReaderHighlights.words[difficult]`. They are
/// worked out only while the highlight is on (`enabled && difficult` in the
/// [HighlightPrefs]) and only for the current chapter:
///
/// - the candidates of a chapter come from [ChapterDifficultWords.candidates]
///   once, asynchronously; a change of chapter, or switching the highlight
///   off, cancels a calculation that is still running;
/// - a new level, threshold, mark "known" or looked-up word (a term with a
///   lookup count above 0, T-121) only re-picks from the candidates
///   ([ChapterDifficultWords.pick]), the text is not analysed again: the
///   candidates hold every lemma of the chapter, also those of an unknown
///   level and proper names, so a word looked up just now is already there;
/// - with the highlight off nothing is read: neither the use case nor the
///   terms, and [onChanged] gets an empty set.
///
/// [onChanged] is called only when the set differs from the last one sent
/// (initially empty).
final class DifficultWordsTracker {
  /// Creates a tracker for [book].
  ///
  /// [useCase] and [terms] are asked for lazily, on the first need, so a
  /// reader with the highlight off does not touch those ports.
  new({
    required this.bookId,
    required this.book,
    required this.useCase,
    required this.terms,
    required this.onChanged,
  });

  /// The book the chapters belong to.
  final BookId bookId;

  /// The opened book: the chapter text is read from it.
  final OpenedBook book;

  /// Gives the use case when the first calculation starts.
  final ChapterDifficultWords Function() useCase;

  /// Gives the term repository when the highlight is first on.
  final TermRepository Function() terms;

  /// Receives the new set of lemmas; never changed afterwards.
  final void Function(Set<String> words) onChanged;

  ChapterRef? _chapter;
  HighlightPrefs _prefs = const HighlightPrefs();
  CefrLevel _level = const UserProfile().level;
  Set<String>? _known;
  Map<String, int> _lookedUp = const {};
  StreamSubscription<List<Term>>? _termsSub;
  List<CheatSheetItem>? _candidates;
  ChapterRef? _candidatesOf;
  CancelToken? _running;
  Set<String> _sent = const {};
  bool _disposed = false;

  bool get _active => _prefs.enabled && _prefs.difficult && _chapter != null;

  /// The reader moved to [chapter]; the set of the old chapter is dropped.
  void setChapter(ChapterRef chapter) {
    if (_chapter == chapter) return;
    _chapter = chapter;
    _running?.cancel();
    _running = null;
    _candidates = null;
    _candidatesOf = null;
    _send(const {});
    _update();
  }

  /// The profile changed: takes the level and the highlight prefs from it.
  void setProfile(UserProfile profile) {
    if (profile.level == _level && profile.highlights == _prefs) return;
    _level = profile.level;
    _prefs = profile.highlights;
    _update();
  }

  /// Stops all work; [onChanged] is not called any more.
  void dispose() {
    _disposed = true;
    _running?.cancel();
    _running = null;
    unawaited(_termsSub?.cancel());
    _termsSub = null;
  }

  void _send(Set<String> words) {
    if (_disposed || setEquals(words, _sent)) return;
    _sent = words;
    onChanged(words);
  }

  void _update() {
    if (_disposed) return;
    if (!_active) {
      _running?.cancel();
      _running = null;
      unawaited(_termsSub?.cancel());
      _termsSub = null;
      _known = null;
      _lookedUp = const {};
      _send(const {});
      return;
    }
    _watchTerms();
    final known = _known;
    if (known == null) return; // The first answer of the stream calls again.
    final chapter = _chapter!;
    if (_candidatesOf != chapter || _candidates == null) {
      _calculate(chapter);
      return;
    }
    _send(
      useCase().pick(
        _candidates!,
        level: _level,
        minBars: _prefs.minFrequencyBars,
        known: known,
        lookedUp: _lookedUp,
      ),
    );
  }

  void _watchTerms() {
    if (_termsSub != null) return;
    _termsSub = terms().watchAll().listen(
      (list) {
        final known = <String>{};
        final lookedUp = <String, int>{};
        for (final t in list) {
          if (t.language != cheatSheetLanguage) continue;
          if (t.status == TermStatus.known) {
            known.add(t.normalized);
          } else if (t.lookupCount > 0) {
            lookedUp[t.normalized] = t.lookupCount;
          }
        }
        _known = known;
        _lookedUp = lookedUp;
        _update();
      },
      onError: (Object e, StackTrace s) {
        _log.warning('Watching the terms failed', e, s);
        // Without the terms the words are still highlighted by level.
        _known ??= const {};
        _update();
      },
    );
  }

  void _calculate(ChapterRef chapter) {
    if (_running != null) return;
    final cancel = CancelToken();
    _running = cancel;
    unawaited(_run(chapter, cancel));
  }

  Future<void> _run(ChapterRef chapter, CancelToken cancel) async {
    try {
      final items = await useCase().candidates(
        book,
        bookId,
        chapter,
        cancel: cancel,
      );
      if (cancel.isCancelled || _disposed) return;
      _running = null;
      _candidates = items;
      _candidatesOf = chapter;
    } on CancelledException {
      return;
    } on Object catch (e, s) {
      if (cancel.isCancelled || _disposed) return;
      _log.warning('Finding the difficult words of $chapter failed', e, s);
      _running = null;
      // Marked as done with nothing found: no retry loop on every profile
      // change; the next chapter tries again.
      _candidates = const [];
      _candidatesOf = chapter;
    }
    _update();
  }
}
