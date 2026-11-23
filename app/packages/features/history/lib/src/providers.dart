import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One place where a term was looked up.
class HistoryContext {
  /// Creates a context.
  const new({required this.event, required this.book});

  /// The journal entry.
  final LookupEvent event;

  /// Book of the lookup, `null` if the event has no locator or the book is
  /// gone from the library.
  final Book? book;

  /// The sentence around the lookup, falling back to the looked-up text.
  String get sentence => event.query.sentence ?? event.query.text;
}

/// A term of the history with its lookups.
class HistoryEntry {
  /// Creates an entry.
  const new({required this.term, required this.contexts});

  /// The term.
  final Term term;

  /// Lookups of the term, newest first. Journal entries that cannot be found
  /// are skipped.
  final List<HistoryContext> contexts;

  /// Time of the last lookup, `null` if no entry of the journal is left.
  DateTime? get lastAt => contexts.isEmpty ? null : contexts.first.event.at;

  /// Short gloss: the first sense of the latest answer, empty if none.
  String get gloss {
    for (final c in contexts) {
      final senses = c.event.result.senses;
      if (senses.isNotEmpty) return senses.first.text;
    }
    return '';
  }

  /// Book of the latest lookup that has one.
  Book? get book {
    for (final c in contexts) {
      if (c.book != null) return c.book;
    }
    return null;
  }
}

/// Books of the library, for the filter.
final StreamProvider<List<Book>> historyBooksProvider =
    StreamProvider<List<Book>>(
      (ref) => ref.watch(bookRepositoryProvider).watchAll(),
      name: 'historyBooksProvider',
    );

/// Terms with their lookups, the most recently looked up first.
///
/// With a book only terms looked up in that book remain, and only their
/// lookups in that book are listed.
final Provider<AsyncValue<List<HistoryEntry>>> Function(BookId?)
historyProvider = Provider.family<AsyncValue<List<HistoryEntry>>, BookId?>((
  ref,
  book,
) {
  final terms = ref.watch(_termsProvider);
  final events = ref.watch(_eventsProvider);
  final books = ref.watch(historyBooksProvider);
  for (final value in [terms, events, books]) {
    if (value.hasError) {
      return AsyncError(value.error!, value.stackTrace!);
    }
  }
  final termList = terms.value;
  final eventList = events.value;
  final bookList = books.value;
  if (termList == null || eventList == null || bookList == null) {
    return const AsyncLoading();
  }
  final byId = {for (final e in eventList) e.id: e};
  final bookById = {for (final b in bookList) b.id: b};
  final entries = <HistoryEntry>[];
  for (final term in termList) {
    final contexts = <HistoryContext>[
      for (final id in term.eventIds)
        if (byId[id] case final event?)
          if (book == null || event.query.locator?.book == book)
            HistoryContext(
              event: event,
              book: bookById[event.query.locator?.book],
            ),
    ]..sort((a, b) => b.event.at.compareTo(a.event.at));
    if (book != null && contexts.isEmpty) continue;
    entries.add(HistoryEntry(term: term, contexts: contexts));
  }
  entries.sort((a, b) {
    final x = a.lastAt;
    final y = b.lastAt;
    if (x == null || y == null) {
      return x == y ? 0 : (x == null ? 1 : -1);
    }
    return y.compareTo(x);
  });
  return AsyncData(entries);
}, name: 'historyProvider').call;

final StreamProvider<List<Term>> _termsProvider = StreamProvider<List<Term>>(
  (ref) => ref.watch(termRepositoryProvider).watchAll(),
  name: 'historyTermsProvider',
);

final StreamProvider<List<LookupEvent>> _eventsProvider =
    StreamProvider<List<LookupEvent>>(
      (ref) => ref.watch(lookupJournalProvider).watch(),
      name: 'historyEventsProvider',
    );

/// Translated phrases, the newest first.
final StreamProvider<List<PhraseLookup>> historyPhrasesProvider =
    StreamProvider<List<PhraseLookup>>(
      (ref) => ref.watch(phraseJournalProvider).watchAll(),
      name: 'historyPhrasesProvider',
    );
