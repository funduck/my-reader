import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:drift/drift.dart';

import 'converters.dart';

/// Library of books (`Book`).
@DataClassName('BookRow')
@TableIndex(name: 'books_content_hash', columns: {#contentHash})
class Books extends Table {
  /// `BookId.value`.
  TextColumn get id => text()();

  /// Title of the book.
  TextColumn get title => text()();

  /// Author, if known.
  TextColumn get author => text().nullable()();

  /// BCP 47 language tag, if known.
  TextColumn get language => text().nullable()();

  /// `BookFormat` name.
  TextColumn get format => textEnum<BookFormat>()();

  /// Path of the book file.
  TextColumn get filePath => text()();

  /// Content hash, used for the duplicate check.
  TextColumn get contentHash => text()();

  /// When the book was added, microseconds since epoch (UTC).
  IntColumn get addedAt => integer().map(const UtcDateTimeConverter())();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Last reading position of each book (`ReadingProgress`).
///
/// No foreign key to [Books]: progress is removed explicitly in
/// `BookRepository.remove`, and the repository contract allows saving
/// progress of a book that is not in the library.
@DataClassName('ProgressRow')
class ReadingProgressTable extends Table {
  @override
  String get tableName => 'reading_progress';

  /// `BookId.value`.
  TextColumn get bookId => text()();

  /// `Locator` as JSON.
  TextColumn get locator => text().map(const LocatorConverter())();

  /// Fraction of the whole book read, 0..1.
  RealColumn get percent => real()();

  /// When the position was saved, microseconds since epoch (UTC).
  IntColumn get updatedAt => integer().map(const UtcDateTimeConverter())();

  @override
  Set<Column<Object>> get primaryKey => {bookId};
}

/// The single profile row (`UserProfile`), id is always [singleRowId].
@DataClassName('ProfileRow')
class ProfileTable extends Table {
  @override
  String get tableName => 'profile';

  /// Always [singleRowId].
  IntColumn get id => integer()();

  /// `UserProfile` as JSON.
  TextColumn get data => text().map(const UserProfileConverter())();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Id of the only row of the profile table.
const int singleRowId = 1;

/// Journal of lookups (`LookupEvent`), append-only.
///
/// The book and chapter of the event are copied out of the locator so the
/// journal can be filtered in SQL.
@DataClassName('LookupEventRow')
@TableIndex(name: 'lookup_events_at', columns: {#at})
@TableIndex(name: 'lookup_events_book', columns: {#bookId, #chapterIndex})
class LookupEvents extends Table {
  /// `LookupEventId.value`.
  TextColumn get id => text()();

  /// When the lookup happened, microseconds since epoch (UTC).
  IntColumn get at => integer().map(const UtcDateTimeConverter())();

  /// Selected text.
  TextColumn get queryText => text()();

  /// `LookupMode` name.
  TextColumn get mode => textEnum<LookupMode>()();

  /// Context sentence, if known.
  TextColumn get sentence => text().nullable()();

  /// `Locator` as JSON, null if the query did not come from reading.
  TextColumn get locator => text().map(const LocatorConverter()).nullable()();

  /// `Locator.book`, copied for filtering.
  TextColumn get bookId => text().nullable()();

  /// `Locator.chapter.href`, copied for filtering.
  TextColumn get chapterHref => text().nullable()();

  /// `Locator.chapter.index`, copied for filtering.
  IntColumn get chapterIndex => integer().nullable()();

  /// `ProviderId.value` of the answer.
  TextColumn get provider => text()();

  /// IPA transcription of the answer, if known.
  TextColumn get transcription => text().nullable()();

  /// List of `Sense` as JSON.
  TextColumn get senses => text().map(const SensesConverter())();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Words and phrases aggregated from the journal (`Term`).
@DataClassName('TermRow')
@TableIndex(
  name: 'terms_lemma',
  columns: {#normalized, #language},
  unique: true,
)
class Terms extends Table {
  /// `TermId.value`.
  TextColumn get id => text()();

  /// Normalized form (lemma).
  TextColumn get normalized => text()();

  /// Language code, for example `en`.
  TextColumn get language => text()();

  /// How many times the term was looked up.
  IntColumn get lookupCount => integer()();

  /// `TermStatus` name.
  TextColumn get status => textEnum<TermStatus>()();

  /// `CefrLevel` name.
  TextColumn get level => textEnum<CefrLevel>()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Links a term to the journal events that mention it.
///
/// No foreign keys, like the rest of the schema.
@DataClassName('TermEventRow')
@TableIndex(name: 'term_events_event', columns: {#eventId})
class TermEvents extends Table {
  /// `TermId.value`.
  TextColumn get termId => text()();

  /// `LookupEventId.value`.
  TextColumn get eventId => text()();

  /// Order of the event inside `Term.eventIds`, from 0.
  IntColumn get position => integer()();

  @override
  Set<Column<Object>> get primaryKey => {termId, eventId};
}
