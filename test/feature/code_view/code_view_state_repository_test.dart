import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/code_view_state_repository.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/code_view_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase database;
  late CodeViewStateRepositoryImpl repository;
  late int projectId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = CodeViewStateRepositoryImpl(database: database);
    projectId = await database
        .into(database.projectsTable)
        .insert(ProjectsTableCompanion.insert(path: '/work/app', name: 'app'));
  });

  tearDown(() => database.close());

  test('load without a row is the default', () async {
    expect(await repository.load(projectId), const CodeViewState());
  });

  test('save then load round-trips', () async {
    const state = CodeViewState(
      mode: CodeViewMode.code,
      tabs: <String>['lib/main.dart', 'pubspec.yaml'],
      activeTab: 'pubspec.yaml',
      explorerWidth: 300,
    );

    await repository.save(projectId, state);
    await repository.save(projectId, state.copyWith(explorerWidth: 320));

    expect(await repository.load(projectId), state.copyWith(explorerWidth: 320));
  });

  test('an unknown mode reads as chat', () async {
    await database.customStatement(
      "INSERT INTO code_view_state (project_id, mode) VALUES ($projectId, 'split')",
    );

    expect((await repository.load(projectId)).mode, CodeViewMode.chat);
  });

  test('broken tabs JSON reads as no tabs', () async {
    await database.customStatement(
      "INSERT INTO code_view_state (project_id, tabs) VALUES ($projectId, 'not json')",
    );

    expect((await repository.load(projectId)).tabs, isEmpty);
  });

  test('deleting the project deletes its row', () async {
    await repository.save(projectId, const CodeViewState(mode: CodeViewMode.code));

    await (database.delete(database.projectsTable)..where((row) => row.id.equals(projectId))).go();

    expect(await database.select(database.codeViewStateTable).get(), isEmpty);
  });
}
