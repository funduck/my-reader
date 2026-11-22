/// SQLite storage through drift, all repositories.
///
/// Open the database with `openDatabase` (file) or `openInMemory` (tests) and
/// take repositories from the returned `AppDatabase`.
library;

export 'src/database.dart' show AppDatabase, openDatabase, openInMemory;
