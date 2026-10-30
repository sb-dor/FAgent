import 'dart:io' as io;

import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:path/path.dart' as p;

/// Whether agents may run a folder's settings and hooks.
abstract interface class IProjectTrustRepository {
  /// Claude settings files in [projectPath] that an agent would execute
  /// (relative paths), shown in the trust dialog.
  Future<List<String>> agentSettingsFiles(String projectPath);

  /// Records the user's trust in project [projectId].
  Future<void> trust(int projectId);
}

/// Drift and file system backed [IProjectTrustRepository].
final class ProjectTrustRepositoryImpl implements IProjectTrustRepository {
  /// Creates the repository.
  ProjectTrustRepositoryImpl({required this._database});

  final AppDatabase _database;

  static const List<String> _candidates = <String>[
    '.claude/settings.json',
    '.claude/settings.local.json',
    '.mcp.json',
    'CLAUDE.md',
  ];

  @override
  Future<List<String>> agentSettingsFiles(String projectPath) async => <String>[
    for (final relative in _candidates)
      if (io.File(p.join(projectPath, relative)).existsSync()) relative,
    if (io.Directory(p.join(projectPath, '.claude', 'hooks')).existsSync()) '.claude/hooks/',
  ];

  @override
  Future<void> trust(int projectId) =>
      (_database.update(_database.projectsTable)..where((p) => p.id.equals(projectId))).write(
        ProjectsTableCompanion(trustedAt: Value<DateTime>(DateTime.now())),
      );
}
