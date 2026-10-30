import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';

/// A project cannot be removed while an agent works in one of its chats.
class ProjectBusyException implements Exception {
  /// Creates the exception for project [projectId].
  const ProjectBusyException(this.projectId);

  /// The project that was not removed.
  final int projectId;

  @override
  String toString() => 'ProjectBusyException: an agent works in a chat of project $projectId';
}

/// Projects in the sidebar.
abstract interface class IProjectsRepository {
  /// Every project, most recently opened first. Closes when cancelled.
  Stream<List<Project>> watchProjects();

  /// Forgets project [projectId]; its chats and their events are deleted with it, the folder on
  /// disk stays.
  ///
  /// Throws [ProjectBusyException], and deletes nothing, while an agent works in one of its chats:
  /// the agent would go on editing files with no chat to answer its permission requests, and the
  /// journal of the chat could no longer be written.
  Future<void> remove(int projectId);

  /// Shows [path] in Finder.
  Future<void> reveal(String path);

  /// Opens [path] with the application the system picks for it.
  Future<void> openPath(String path);
}

/// Drift-backed [IProjectsRepository].
final class ProjectsRepositoryImpl implements IProjectsRepository {
  /// Creates the repository.
  ProjectsRepositoryImpl({required this._database, required this._hub});

  final AppDatabase _database;
  final AgentHub _hub;

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
  Future<void> remove(int projectId) async {
    final chats = await (_database.select(
      _database.sessionsTable,
    )..where((s) => s.projectId.equals(projectId))).get();
    if (chats.any((chat) => _hub.opened(chat.id)?.status.value.isBusy ?? false)) {
      throw ProjectBusyException(projectId);
    }
    await (_database.delete(_database.projectsTable)..where((p) => p.id.equals(projectId))).go();
  }

  @override
  Future<void> reveal(String path) async {
    final result = await Process.run('open', <String>['-R', path]);
    if (result.exitCode != 0) {
      throw ProcessException('open', <String>['-R', path], '${result.stderr}', result.exitCode);
    }
  }

  @override
  Future<void> openPath(String path) async {
    final result = await Process.run('open', <String>[path]);
    if (result.exitCode != 0) {
      throw ProcessException('open', <String>[path], '${result.stderr}', result.exitCode);
    }
  }
}
