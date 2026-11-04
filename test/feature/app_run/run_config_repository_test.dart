import 'dart:io' as io;

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/launch_config_reader.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/run_config_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_arguments.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase database;
  late RunConfigRepositoryImpl repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = RunConfigRepositoryImpl(database: database);
  });
  tearDown(() => database.close());

  Future<int> insertProject(String path) => database
      .into(database.projectsTable)
      .insert(ProjectsTableCompanion.insert(path: path, name: 'app'));

  const dev = RunArguments(
    flavor: 'dev',
    dartDefines: <String>['API=https://dev', 'DEBUG=1'],
    extraArgs: '--no-sound-null-safety',
  );

  test('a project without a row has no arguments', () async {
    final project = await insertProject('/work/app');
    expect(await repository.watch(project).first, const RunArguments());
  });

  test('save stores the arguments of that project only, and a second save replaces them', () async {
    final first = await insertProject('/work/a');
    final second = await insertProject('/work/b');

    await repository.save(first, dev);
    expect(await repository.watch(first).first, dev);
    expect(await repository.watch(second).first, const RunArguments());

    await repository.save(first, const RunArguments(dartDefines: <String>['X=1']));
    expect(await repository.watch(first).first, const RunArguments(dartDefines: <String>['X=1']));
    expect(await database.select(database.runConfigsTable).get(), hasLength(1));
  });

  test('watch emits again when the arguments are saved', () async {
    final project = await insertProject('/work/app');
    final seen = <RunArguments>[];
    final subscription = repository.watch(project).listen(seen.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    await repository.save(project, dev);
    await pumpEventQueue();

    expect(seen, const <RunArguments>[RunArguments(), dev]);
  });

  test('a define with a comma or a newline survives the round trip', () async {
    final project = await insertProject('/work/app');
    const tricky = RunArguments(dartDefines: <String>['LIST=a,b', 'Q="x y"', 'EMPTY=']);
    await repository.save(project, tricky);
    expect(await repository.watch(project).first, tricky);
  });

  test('deleting the project deletes its row', () async {
    final project = await insertProject('/work/app');
    await repository.save(project, dev);
    expect(await database.select(database.runConfigsTable).get(), hasLength(1));

    await (database.delete(database.projectsTable)..where((row) => row.id.equals(project))).go();

    expect(await database.select(database.runConfigsTable).get(), isEmpty);
  });

  test('a damaged stored list reads as no defines', () async {
    final project = await insertProject('/work/app');
    await database.customStatement(
      'INSERT INTO run_configs (project_id, flavor, dart_defines, extra_args) '
      "VALUES ($project, 'dev', 'not json', '')",
    );
    expect(await repository.watch(project).first, const RunArguments(flavor: 'dev'));
  });

  test('selection round-trips and null is Default', () async {
    final project = await insertProject('/work/app');
    expect(await repository.watchSelected(project).first, isNull);

    await repository.saveSelected(project, 'Run PROD');
    expect(await repository.watchSelected(project).first, 'Run PROD');
    expect(
      await repository.watch(project).first,
      const RunArguments(),
      reason: 'a row with only the selection has no arguments',
    );

    await repository.save(project, dev);
    expect(
      await repository.watchSelected(project).first,
      'Run PROD',
      reason: 'saving the arguments keeps the selection',
    );

    await repository.saveSelected(project, null);
    expect(await repository.watchSelected(project).first, isNull);
    expect(
      await repository.watch(project).first,
      dev,
      reason: 'choosing Default keeps the arguments',
    );
    expect(await database.select(database.runConfigsTable).get(), hasLength(1));
  });

  test('choosing Default for a project without a row stores nothing', () async {
    final project = await insertProject('/work/app');
    await repository.saveSelected(project, null);
    expect(await database.select(database.runConfigsTable).get(), isEmpty);
  });

  test('watchSelected emits again when the selection is saved', () async {
    final project = await insertProject('/work/app');
    final seen = <String?>[];
    final subscription = repository.watchSelected(project).listen(seen.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    await repository.saveSelected(project, 'Dev');
    await pumpEventQueue();

    expect(seen, <String?>[null, 'Dev']);
  });

  test('saving the selection does not re-emit the arguments', () async {
    final project = await insertProject('/work/app');
    await repository.save(project, dev);
    final seen = <RunArguments>[];
    final subscription = repository.watch(project).listen(seen.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    await repository.saveSelected(project, 'Prod');
    await pumpEventQueue();

    expect(seen, const <RunArguments>[dev]);
  });

  test('launchConfigs reads the launch.json of the project folder on every call', () async {
    final root = io.Directory.systemTemp.createTempSync('run_config_repository_test');
    addTearDown(() => root.deleteSync(recursive: true));
    final project = await insertProject(root.path);
    expect(await repository.launchConfigs(project), isA<LaunchConfigsMissing>());

    final file = io.File(p.join(root.path, '.vscode', 'launch.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '{"configurations": [{"name": "Dev", "type": "dart", "request": "launch"}]}',
      );
    final read = await repository.launchConfigs(project);
    expect((read as LaunchConfigsRead).configs.single.name, 'Dev');

    file.writeAsStringSync(
      '{"configurations": [{"name": "Prod", "type": "dart", "request": "launch"}]}',
    );
    final again = await repository.launchConfigs(project);
    expect((again as LaunchConfigsRead).configs.single.name, 'Prod');
  });

  test('launchConfigs of an unknown project is missing', () async {
    expect(await repository.launchConfigs(42), isA<LaunchConfigsMissing>());
  });
}
