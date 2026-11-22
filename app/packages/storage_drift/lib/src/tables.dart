import 'package:core/domain_books.dart';
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
