import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/pub_workspace/pub_workspace.dart' as pub_workspace;
import 'package:flutter_code_agent/src/feature/app_run/data/launch_config_reader.dart' as reader;
import 'package:flutter_code_agent/src/feature/app_run/models/run_arguments.dart';

/// The arguments each project and each of its apps add to `flutter run`, the `.vscode/launch.json`
/// configuration and the app it runs, and the configurations that file holds.
abstract interface class IRunConfigRepository {
  /// The arguments of the app at [appFolder] in [projectId] (`''` for the project root), then
  /// every change; [RunArguments] with nothing set while the app has none. Cancel the subscription
  /// to stop watching.
  Stream<RunArguments> watch(int projectId, {String appFolder = ''});

  /// Replaces the arguments of the app at [appFolder] in [projectId] (`''` for the project root).
  /// The selected configuration and app stay.
  Future<void> save(int projectId, RunArguments arguments, {String appFolder = ''});

  /// The name of the configuration [projectId] runs, then every change; `null` for Default (the
  /// project's [RunArguments]). Cancel the subscription to stop watching.
  Stream<String?> watchSelected(int projectId);

  /// Stores [name] as the configuration [projectId] runs; `null` goes back to Default. The
  /// arguments stay.
  Future<void> saveSelected(int projectId, String? name);

  /// The folder of the app the monorepo [projectId] runs (`apps/desktop`), then every change;
  /// `null` while none is chosen. Cancel the subscription to stop watching.
  Stream<String?> watchSelectedApp(int projectId);

  /// Stores [appFolder] as the app [projectId] runs; `null` clears the choice. The arguments and
  /// the selected configuration stay.
  Future<void> saveSelectedApp(int projectId, String? appFolder);

  /// Whether [projectId] is a monorepo (a pub workspace root without an app of its own), read from
  /// disk on every call; `false` for a project whose folder is unknown.
  Future<bool> isMonorepo(int projectId);

  /// The folders of the apps the monorepo [projectId] can run (`apps/desktop`), read from disk on
  /// every call; empty for a one-app project or one whose folder is unknown.
  Future<List<String>> runnableApps(int projectId);

  /// Reads the `.vscode/launch.json` of [projectId] from disk, anew on every call; a project whose
  /// folder is unknown has none.
  Future<reader.LaunchConfigs> launchConfigs(int projectId);
}

/// [IRunConfigRepository] over the `run_configs` table.
final class RunConfigRepositoryImpl implements IRunConfigRepository {
  /// Creates the repository.
  RunConfigRepositoryImpl({required this._database});

  final AppDatabase _database;

  @override
  Stream<RunArguments> watch(int projectId, {String appFolder = ''}) =>
      (_database.select(_database.runConfigsTable)
            ..where((row) => row.projectId.equals(projectId) & row.appFolder.equals(appFolder)))
          .watchSingleOrNull()
          .map((row) => row == null ? const RunArguments() : _decode(row))
          // A saved selection changes the row, not the arguments.
          .distinct();

  @override
  Future<void> save(int projectId, RunArguments arguments, {String appFolder = ''}) => _database
      .into(_database.runConfigsTable)
      .insertOnConflictUpdate(
        RunConfigsTableCompanion.insert(
          projectId: projectId,
          appFolder: Value(appFolder),
          flavor: Value(arguments.flavor),
          dartDefines: Value(jsonEncode(arguments.dartDefines)),
          extraArgs: Value(arguments.extraArgs),
        ),
      );

  @override
  Stream<String?> watchSelected(int projectId) =>
      _watchRootColumn(projectId, _database.runConfigsTable.selectedConfig);

  @override
  Future<void> saveSelected(int projectId, String? name) => _saveRootColumn(
    projectId,
    RunConfigsTableCompanion(selectedConfig: Value<String?>(name)),
    clear: name == null,
  );

  @override
  Stream<String?> watchSelectedApp(int projectId) =>
      _watchRootColumn(projectId, _database.runConfigsTable.selectedApp);

  @override
  Future<void> saveSelectedApp(int projectId, String? appFolder) => _saveRootColumn(
    projectId,
    RunConfigsTableCompanion(selectedApp: Value<String?>(appFolder)),
    clear: appFolder == null,
  );

  @override
  Future<bool> isMonorepo(int projectId) async {
    final project = await _project(projectId);
    return project != null && pub_workspace.isPubMonorepo(project.path);
  }

  @override
  Future<List<String>> runnableApps(int projectId) async {
    final project = await _project(projectId);
    if (project == null || !pub_workspace.isPubMonorepo(project.path)) return const <String>[];
    return <String>[for (final app in pub_workspace.runnableApps(project.path)) app.folder];
  }

  @override
  Future<reader.LaunchConfigs> launchConfigs(int projectId) async {
    final project = await _project(projectId);
    if (project == null) return const reader.LaunchConfigsMissing();
    return reader.readLaunchConfigs(project.path);
  }

  Future<ProjectRow?> _project(int projectId) => (_database.select(
    _database.projectsTable,
  )..where((row) => row.id.equals(projectId))).getSingleOrNull();

  /// [column] of the root row of [projectId], then every change.
  Stream<String?> _watchRootColumn(int projectId, GeneratedColumn<String> column) =>
      (_database.selectOnly(_database.runConfigsTable)
            ..addColumns(<Expression<Object>>[column])
            ..where(_isRootRow(projectId)))
          .watchSingleOrNull()
          .map((row) => row?.read(column))
          .distinct();

  /// Writes [values] into the root row of [projectId], creating the row unless the write [clear]s
  /// a value: no row already means nothing is stored.
  Future<void> _saveRootColumn(
    int projectId,
    RunConfigsTableCompanion values, {
    required bool clear,
  }) async {
    if (clear) {
      await (_database.update(
        _database.runConfigsTable,
      )..where((_) => _isRootRow(projectId))).write(values);
      return;
    }
    await _database
        .into(_database.runConfigsTable)
        .insertOnConflictUpdate(values.copyWith(projectId: Value(projectId)));
  }

  Expression<bool> _isRootRow(int projectId) =>
      _database.runConfigsTable.projectId.equals(projectId) &
      _database.runConfigsTable.appFolder.equals('');

  RunArguments _decode(RunConfigRow row) => RunArguments(
    flavor: row.flavor,
    dartDefines: _decodeDefines(row.dartDefines),
    extraArgs: row.extraArgs,
  );

  /// A list that cannot be read counts as no defines: a damaged row must not stop the project from
  /// running.
  List<String> _decodeDefines(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is List<Object?>) return decoded.whereType<String>().toList(growable: false);
    } on FormatException {
      // Falls through to no defines.
    }
    return const <String>[];
  }
}
