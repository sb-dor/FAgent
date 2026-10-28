import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';

/// Projects in the sidebar.
abstract interface class IProjectsRepository {
  /// Every project, most recently opened first. Closes when cancelled.
  Stream<List<Project>> watchProjects();

  /// Forgets project [projectId]; its chats and their events are deleted with it, the folder on
  /// disk stays.
  Future<void> remove(int projectId);

  /// Shows [path] in Finder.
  Future<void> reveal(String path);
}

/// Drift-backed [IProjectsRepository].
final class ProjectsRepositoryImpl implements IProjectsRepository {
  /// Creates the repository.
  ProjectsRepositoryImpl({required this._database});

  final AppDatabase _database;

  @override
  Stream<List<Project>> watchProjects() =>
      (_database.select(_database.projectsTable)
            ..orderBy(<OrderClauseGenerator<$ProjectsTableTable>>[
              (p) => OrderingTerm.desc(
                coalesce<DateTime>(<Expression<DateTime>>[p.lastOpenedAt, p.createdAt]),
              ),
            ]))
          .watch()
          .map((rows) => rows.map(Project.fromRow).toList(growable: false));

  // The foreign keys cascade (`PRAGMA foreign_keys = ON`): chats and events go with the project.
  @override
  Future<void> remove(int projectId) =>
      (_database.delete(_database.projectsTable)..where((p) => p.id.equals(projectId))).go();

  @override
  Future<void> reveal(String path) async {
    final result = await Process.run('open', <String>['-R', path]);
    if (result.exitCode != 0) {
      throw ProcessException('open', <String>['-R', path], '${result.stderr}', result.exitCode);
    }
  }
}
