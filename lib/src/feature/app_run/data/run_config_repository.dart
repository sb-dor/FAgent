import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_arguments.dart';

/// The arguments each project adds to `flutter run`.
abstract interface class IRunConfigRepository {
  /// The arguments of [projectId], then every change; [RunArguments] with nothing set while the
  /// project has none. Cancel the subscription to stop watching.
  Stream<RunArguments> watch(int projectId);

  /// Replaces the arguments of [projectId].
  Future<void> save(int projectId, RunArguments arguments);
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
          .map((row) => row == null ? const RunArguments() : _decode(row));

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
