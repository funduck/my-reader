import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:drift/drift.dart';

import 'database.dart';
import 'tables.dart';

/// [BookRepository] on top of `AppDatabase`.
final class DriftBookRepository implements BookRepository {
  /// Creates a repository over the database.
  new(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Book>> watchAll() {
    final query = _db.select(_db.books)
      ..orderBy([
        (t) => OrderingTerm.desc(t.addedAt),
        (t) => OrderingTerm.desc(t.id),
      ]);
    return query.watch().map((rows) => rows.map(_toBook).toList());
  }

  @override
  Future<Book?> get(BookId id) async {
    final row = await (_db.select(
      _db.books,
    )..where((t) => t.id.equals(id.value))).getSingleOrNull();
    return row == null ? null : _toBook(row);
  }

  @override
  Future<Book?> findByContentHash(String contentHash) async {
    final row =
        await (_db.select(_db.books)
              ..where((t) => t.contentHash.equals(contentHash))
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _toBook(row);
  }

  @override
  Future<void> save(Book book) => _db
      .into(_db.books)
      .insertOnConflictUpdate(
        BooksCompanion.insert(
          id: book.id.value,
          title: book.metadata.title,
          author: Value(book.metadata.author),
          language: Value(book.metadata.language),
          format: book.format,
          filePath: book.filePath,
          contentHash: book.contentHash,
          addedAt: book.addedAt,
        ),
      );

  @override
  Future<void> remove(BookId id) => _db.transaction(() async {
    await (_db.delete(
      _db.readingProgressTable,
    )..where((t) => t.bookId.equals(id.value))).go();
    await (_db.delete(_db.books)..where((t) => t.id.equals(id.value))).go();
  });

  Book _toBook(BookRow row) => Book(
    id: BookId(row.id),
    metadata: BookMetadata(
      title: row.title,
      author: row.author,
      language: row.language,
    ),
    format: row.format,
    filePath: row.filePath,
    contentHash: row.contentHash,
    addedAt: row.addedAt,
  );
}

/// [ProgressRepository] on top of `AppDatabase`.
final class DriftProgressRepository implements ProgressRepository {
  /// Creates a repository over the database.
  new(this._db);

  final AppDatabase _db;

  SimpleSelectStatement<$ReadingProgressTableTable, ProgressRow> _select(
    BookId book,
  ) =>
      _db.select(_db.readingProgressTable)
        ..where((t) => t.bookId.equals(book.value));

  @override
  Future<ReadingProgress?> get(BookId book) async {
    final row = await _select(book).getSingleOrNull();
    return row == null ? null : _toProgress(row);
  }

  @override
  Stream<ReadingProgress?> watch(BookId book) =>
      _select(book)
          .watchSingleOrNull()
          .map((row) => row == null ? null : _toProgress(row))
          .distinct();

  @override
  Future<void> save(ReadingProgress progress) => _db
      .into(_db.readingProgressTable)
      .insertOnConflictUpdate(
        ReadingProgressTableCompanion.insert(
          bookId: progress.locator.book.value,
          locator: progress.locator,
          percent: progress.percent,
          updatedAt: progress.updatedAt,
        ),
      );

  ReadingProgress _toProgress(ProgressRow row) => ReadingProgress(
    locator: row.locator,
    percent: row.percent,
    updatedAt: row.updatedAt,
  );
}

/// [ProfileRepository] on top of `AppDatabase`.
final class DriftProfileRepository implements ProfileRepository {
  /// Creates a repository over the database.
  new(this._db);

  final AppDatabase _db;

  SimpleSelectStatement<$ProfileTableTable, ProfileRow> _select() =>
      _db.select(_db.profileTable)..where((t) => t.id.equals(singleRowId));

  @override
  Future<UserProfile> get() async =>
      (await _select().getSingleOrNull())?.data ?? const UserProfile();

  @override
  Stream<UserProfile> watch() => _select()
      .watchSingleOrNull()
      .map((row) => row?.data ?? const UserProfile())
      .distinct();

  @override
  Future<void> save(UserProfile profile) => _db
      .into(_db.profileTable)
      .insertOnConflictUpdate(
        ProfileTableCompanion.insert(
          id: const Value(singleRowId),
          data: profile,
        ),
      );
}
