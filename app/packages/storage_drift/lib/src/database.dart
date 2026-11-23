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
@DriftDatabase(
  tables: [
    Books,
    ReadingProgressTable,
    ProfileTable,
    LookupEvents,
    Terms,
    TermEvents,
    PhraseLookups,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the database on the query executor.
  new(super.e);

  /// Current schema version; bump it and add a step to [migration] together.
  static const int currentSchemaVersion = 3;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // v2: lookup journal and terms.
        await m.createTable(lookupEvents);
        await m.createTable(terms);
        await m.createTable(termEvents);
        // Indexes declared with @TableIndex are separate entities.
        await m.create(lookupEventsAt);
        await m.create(lookupEventsBook);
        await m.create(termsLemma);
        await m.create(termEventsEvent);
      }
      if (from < 3) {
        // v3: phrase journal.
        await m.createTable(phraseLookups);
        await m.create(phraseLookupsAt);
        await m.create(phraseLookupsBook);
      }
    },
  );

  /// Journal of lookups; also lists events of one term.
  DriftLookupJournal get lookupJournal => DriftLookupJournal(this);

  /// Journal of translated phrases.
  DriftPhraseJournal get phraseJournal => DriftPhraseJournal(this);

  /// Terms aggregated from the journal.
  DriftTermRepository get termRepository => DriftTermRepository(this);

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
