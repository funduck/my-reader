import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:storage_drift/src/database.dart';
import 'package:test/test.dart';

import 'generated/schema.g.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('a fresh database matches the dumped schema v1', () async {
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, AppDatabase.currentSchemaVersion);
  });

  test('onCreate builds exactly the dumped schema', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 1);
  });
}
