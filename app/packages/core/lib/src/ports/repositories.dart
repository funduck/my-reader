import 'package:meta/meta.dart';

import '../domain/books/book.dart';
import '../domain/books/chapter_ref.dart';
import '../domain/books/ids.dart';
import '../domain/books/reading_progress.dart';
import '../domain/lookup/cefr_level.dart';
import '../domain/lookup/ids.dart';
import '../domain/lookup/lookup_event.dart';
import '../domain/lookup/term.dart';
import '../domain/lookup/term_status.dart';
import '../domain/profile/user_profile.dart';

/// Library of books (R-4).
///
/// Repository methods are asynchronous; lists are exposed as streams that emit
/// the current value first and then every change.
abstract interface class BookRepository {
  /// Emits all books, newest first.
  Stream<List<Book>> watchAll();

  /// Returns the book with [id], or null if absent.
  Future<Book?> get(BookId id);

  /// Returns the book whose file has [contentHash], or null (duplicate check).
  Future<Book?> findByContentHash(String contentHash);

  /// Inserts the book, or replaces the one with the same id.
  Future<void> save(Book book);

  /// Deletes the book and its progress; history is kept.
  Future<void> remove(BookId id);
}

/// Reading positions (R-2).
abstract interface class ProgressRepository {
  /// Returns the saved progress of [book], or null if never read.
  Future<ReadingProgress?> get(BookId book);

  /// Emits the progress of [book] on every change; null if never read.
  Stream<ReadingProgress?> watch(BookId book);

  /// Saves the progress, replacing the previous one of the same book.
  Future<void> save(ReadingProgress progress);
}

/// Filter for [LookupJournal.watch]; unset fields do not restrict (H-5).
@immutable
final class LookupFilter {
  /// Creates a filter.
  const new({this.book, this.chapter, this.from, this.to, this.level});

  /// Only events made in this book.
  final BookId? book;

  /// Only events made in this chapter (used together with [book]).
  final ChapterRef? chapter;

  /// Only events at or after this moment.
  final DateTime? from;

  /// Only events before this moment.
  final DateTime? to;

  /// Only events whose term has exactly this level.
  final CefrLevel? level;

  @override
  bool operator ==(Object other) =>
      other is LookupFilter &&
      other.book == book &&
      other.chapter == chapter &&
      other.from == from &&
      other.to == to &&
      other.level == level;

  @override
  int get hashCode => Object.hash(book, chapter, from, to, level);
}

/// Append-only journal of lookups (H-1, H-2).
abstract interface class LookupJournal {
  /// Appends an event; ids are unique.
  Future<void> record(LookupEvent event);

  /// Returns the event with [id], or null.
  Future<LookupEvent?> get(LookupEventId id);

  /// Emits events matching [filter], newest first.
  Stream<List<LookupEvent>> watch([LookupFilter filter = const LookupFilter()]);
}

/// Words and phrases aggregated from the journal (H-4).
abstract interface class TermRepository {
  /// Returns the term for a normalized text in [language], or null.
  Future<Term?> find(String normalized, String language);

  /// Emits all terms, optionally only those with [status].
  Stream<List<Term>> watchAll({TermStatus? status});

  /// Inserts the term, or replaces the one with the same id.
  Future<void> save(Term term);
}

/// Profile and settings (U-1, U-2).
abstract interface class ProfileRepository {
  /// Returns the profile; defaults if nothing was saved yet.
  Future<UserProfile> get();

  /// Emits the profile on every change.
  Stream<UserProfile> watch();

  /// Saves the profile.
  ///
  /// Replaces the whole profile: to change part of it use [update], so that
  /// two changes at the same time do not lose one another.
  Future<void> save(UserProfile profile);

  /// Reads the profile, applies [change] and saves the result, with no other
  /// write in between; returns the saved profile (T-120).
  Future<UserProfile> update(UserProfile Function(UserProfile) change);
}
