import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v1.dart' as v1;
import '../../generated_migrations/schema_v2.dart' as v2;
import '../../generated_migrations/schema_v3.dart' as v3;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('v1 → v2 matches the v2 schema and keeps projects', () async {
    final schema = await verifier.schemaAt(1);
    final old = v1.DatabaseAtV1(schema.newConnection());
    await old.customStatement(
      "INSERT INTO projects (path, name, created_at) VALUES ('/work/app', 'app', 0)",
    );
    await old.close();

    final database = AppDatabase(schema.newConnection());
    addTearDown(database.close);
    await verifier.migrateAndValidate(database, 2);

    final project = await database.select(database.projectsTable).getSingle();
    expect(project.path, '/work/app');
    expect(project.isFlutter, isFalse);
    expect(project.trustedAt, isNull);
  });

  test('v2 → v3 matches the v3 schema and keeps chats without bypass consent', () async {
    final schema = await verifier.schemaAt(2);
    final old = v2.DatabaseAtV2(schema.newConnection());
    await old.customStatement(
      "INSERT INTO projects (path, name, created_at) VALUES ('/work/app', 'app', 0)",
    );
    await old.customStatement(
      "INSERT INTO sessions (project_id, agent_id, title) VALUES (1, 'claude', 'chat')",
    );
    await old.close();

    final database = AppDatabase(schema.newConnection());
    addTearDown(database.close);
    await verifier.migrateAndValidate(database, 3);

    final chat = await database.select(database.sessionsTable).getSingle();
    expect(chat.title, 'chat');
    expect(chat.bypassAllowedAt, isNull);
  });

  test('v3 → v4 matches the v4 schema and keeps chats', () async {
    final schema = await verifier.schemaAt(3);
    final old = v3.DatabaseAtV3(schema.newConnection());
    await old.customStatement(
      "INSERT INTO projects (path, name, created_at) VALUES ('/work/app', 'app', 0)",
    );
    await old.customStatement(
      "INSERT INTO sessions (project_id, agent_id, title) VALUES (1, 'claude', 'chat')",
    );
    await old.close();

    final database = AppDatabase(schema.newConnection());
    addTearDown(database.close);
    await verifier.migrateAndValidate(database, 4);

    final chat = await database.select(database.sessionsTable).getSingle();
    expect(chat.title, 'chat');
    expect(await database.select(database.appSettingsTable).get(), isEmpty);
  });
}
