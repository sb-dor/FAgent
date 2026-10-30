import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';

/// Projects in the sidebar.
abstract interface class IProjectsRepository {
  /// Every project, most recently opened first. Closes when cancelled.
  Stream<List<Project>> watchProjects();
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
}
