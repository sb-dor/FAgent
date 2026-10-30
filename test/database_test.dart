import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  Future<int> insertProject([String path = '/tmp/app']) => database
      .into(database.projectsTable)
      .insert(ProjectsTableCompanion.insert(path: path, name: 'app'));

  Future<int> insertSession(int projectId) => database
      .into(database.sessionsTable)
      .insert(SessionsTableCompanion.insert(projectId: projectId, agentId: 'claude'));

  Future<void> insertEvent(int sessionId, int seq) => database
      .into(database.sessionEventsTable)
      .insert(
        SessionEventsTableCompanion.insert(
          sessionId: sessionId,
          seq: seq,
          origin: 'agent',
          kind: 'agent_message_chunk',
          payload: '{}',
        ),
      );

  test('project paths are unique', () async {
    await insertProject();
    expect(insertProject, throwsA(isA<SqliteException>()));
    final projects = await database.select(database.projectsTable).get();
    expect(projects.single.name, 'app');
  });

  test('event seq is unique per session', () async {
    final session = await insertSession(await insertProject());
    await insertEvent(session, 0);

    expect(() => insertEvent(session, 0), throwsA(isA<SqliteException>()));
    final other = await insertSession(await insertProject('/tmp/other'));
    await insertEvent(other, 0);
  });

  test('deleting a project cascades to its sessions and events', () async {
    final project = await insertProject();
    final session = await insertSession(project);
    await insertEvent(session, 0);

    await (database.delete(database.projectsTable)..where((p) => p.id.equals(project))).go();

    expect(await database.select(database.sessionsTable).get(), isEmpty);
    expect(await database.select(database.sessionEventsTable).get(), isEmpty);
  });

  test('events need an existing session', () async {
    expect(() => insertEvent(42, 0), throwsA(isA<SqliteException>()));
  });
}
