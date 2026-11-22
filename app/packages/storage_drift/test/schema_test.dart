import 'dart:convert';

import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:storage_drift/src/database.dart';
import 'package:test/test.dart';

import 'generated/schema.g.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('a fresh v1 database migrates to the current schema', () async {
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, AppDatabase.currentSchemaVersion);
  });

  test('onCreate builds exactly the dumped current schema', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, AppDatabase.currentSchemaVersion);
  });

  test('v1 data survives migration to v2, new tables work', () async {
    final schema = await verifier.schemaAt(1);
    const locator = Locator(
      book: BookId('b1'),
      chapter: ChapterRef(href: 'c1.xhtml', index: 0),
      progression: 0.5,
    );
    final added = DateTime.utc(2024, 1, 2, 3, 4, 5).microsecondsSinceEpoch;
    schema.rawDatabase
      ..execute(
        'INSERT INTO books (id, title, author, language, format, file_path, '
        'content_hash, added_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        ['b1', 'Moby-Dick', 'Melville', 'en', 'epub', '/b1.epub', 'h1', added],
      )
      ..execute(
        'INSERT INTO reading_progress (book_id, locator, percent, updated_at) '
        'VALUES (?, ?, ?, ?)',
        ['b1', jsonEncode(locator.toJson()), 0.5, added],
      )
      ..execute('INSERT INTO profile (id, data) VALUES (1, ?)', [
        jsonEncode(const UserProfile(level: CefrLevel.c1).toJson()),
      ]);

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 2);

    final book = await db.bookRepository.get(const BookId('b1'));
    expect(book?.metadata.title, 'Moby-Dick');
    expect(book?.addedAt, DateTime.utc(2024, 1, 2, 3, 4, 5));
    final progress = await db.progressRepository.get(const BookId('b1'));
    expect(progress?.locator, locator);
    expect((await db.profileRepository.get()).level, CefrLevel.c1);

    // The new tables are empty and usable, including the unique lemma index.
    expect(await db.lookupJournal.watch().first, isEmpty);
    expect(await db.termRepository.watchAll().first, isEmpty);
    await db.termRepository.upsert(
      id: const TermId('t1'),
      lemma: 'run',
      language: 'en',
      event: const LookupEventId('e1'),
    );
    final again = await db.termRepository.upsert(
      id: const TermId('t2'),
      lemma: 'run',
      language: 'en',
      event: const LookupEventId('e2'),
    );
    expect(again.lookupCount, 2);
    expect(await db.termRepository.watchAll().first, hasLength(1));
  });
}
