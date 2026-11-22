import 'dart:io';

import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'converters.dart';
import 'repositories.dart';
import 'tables.dart';

part 'database.g.dart';

/// The application database: one SQLite file behind all repositories.
///
/// Create it with [openDatabase] or [openInMemory]. Tables and generated row
/// classes are internal to this package; the outside sees only the
/// repositories.
@DriftDatabase(tables: [Books, ReadingProgressTable, ProfileTable])
class AppDatabase extends _$AppDatabase {
  /// Opens the database on the query executor.
  new(super.e);

  /// Current schema version; bump it and add a step to [migration] together.
  static const int currentSchemaVersion = 1;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // Add `onUpgrade` steps here for schema v2+ (see drift_schemas/).
  );

  /// Library of books.
  BookRepository get bookRepository => DriftBookRepository(this);

  /// Reading positions.
  ProgressRepository get progressRepository => DriftProgressRepository(this);

  /// Profile and settings.
  ProfileRepository get profileRepository => DriftProfileRepository(this);
}

/// Opens (creating if needed) the database file at [path].
AppDatabase openDatabase(String path) =>
    AppDatabase(NativeDatabase(File(path)));

/// Opens an empty database in memory; for tests.
AppDatabase openInMemory() => AppDatabase(NativeDatabase.memory());
