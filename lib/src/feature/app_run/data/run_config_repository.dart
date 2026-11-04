import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/launch_config_reader.dart' as reader;
import 'package:flutter_code_agent/src/feature/app_run/models/run_arguments.dart';

/// The arguments each project adds to `flutter run`, the `.vscode/launch.json` configuration it
/// runs, and the configurations that file holds.
abstract interface class IRunConfigRepository {
  /// The arguments of [projectId], then every change; [RunArguments] with nothing set while the
  /// project has none. Cancel the subscription to stop watching.
  Stream<RunArguments> watch(int projectId);

  /// Replaces the arguments of [projectId]. The selected configuration stays.
  Future<void> save(int projectId, RunArguments arguments);

  /// The name of the configuration [projectId] runs, then every change; `null` for Default (the
  /// project's [RunArguments]). Cancel the subscription to stop watching.
  Stream<String?> watchSelected(int projectId);

  /// Stores [name] as the configuration [projectId] runs; `null` goes back to Default. The
  /// arguments stay.
  Future<void> saveSelected(int projectId, String? name);

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
  Stream<RunArguments> watch(int projectId) =>
      (_database.select(_database.runConfigsTable)..where((row) => row.projectId.equals(projectId)))
          .watchSingleOrNull()
          .map((row) => row == null ? const RunArguments() : _decode(row))
          // A saved selection changes the row, not the arguments.
          .distinct();

  @override
  Future<void> save(int projectId, RunArguments arguments) => _database
      .into(_database.runConfigsTable)
      .insertOnConflictUpdate(
        RunConfigsTableCompanion.insert(
          projectId: Value(projectId),
          flavor: Value(arguments.flavor),
          dartDefines: Value(jsonEncode(arguments.dartDefines)),
          extraArgs: Value(arguments.extraArgs),
        ),
      );

  @override
  Stream<String?> watchSelected(int projectId) =>
      (_database.selectOnly(_database.runConfigsTable)
            ..addColumns(<Expression<Object>>[_database.runConfigsTable.selectedConfig])
            ..where(_database.runConfigsTable.projectId.equals(projectId)))
          .watchSingleOrNull()
          .map((row) => row?.read(_database.runConfigsTable.selectedConfig))
          .distinct();

  @override
  Future<void> saveSelected(int projectId, String? name) async {
    // Default for a project without a row is what no row means already.
    if (name == null) {
      await (_database.update(_database.runConfigsTable)
            ..where((row) => row.projectId.equals(projectId)))
          .write(const RunConfigsTableCompanion(selectedConfig: Value<String?>(null)));
      return;
    }
    await _database
        .into(_database.runConfigsTable)
        .insertOnConflictUpdate(
          RunConfigsTableCompanion.insert(projectId: Value(projectId), selectedConfig: Value(name)),
        );
  }

  @override
  Future<reader.LaunchConfigs> launchConfigs(int projectId) async {
    final project = await (_database.select(
      _database.projectsTable,
    )..where((row) => row.id.equals(projectId))).getSingleOrNull();
    if (project == null) return const reader.LaunchConfigsMissing();
    return reader.readLaunchConfigs(project.path);
  }

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
