import 'dart:io' as io;

import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:path/path.dart' as p;

/// Adds a folder to the projects (or reopens it).
abstract interface class IProjectOpeningRepository {
  /// Upserts the project at [path], re-checks whether it is a Flutter project
  /// and marks it as just opened.
  Future<Project> open(String path);
}

/// Drift and file system backed [IProjectOpeningRepository].
final class ProjectOpeningRepositoryImpl implements IProjectOpeningRepository {
  /// Creates the repository.
  ProjectOpeningRepositoryImpl({required this._database});

  final AppDatabase _database;

  static final RegExp _flutterDependency = RegExp(r'^\s+flutter:\s*$', multiLine: true);

  @override
  Future<Project> open(String path) async {
    final folder = io.Directory(path);
    if (!folder.existsSync()) throw io.FileSystemException('Folder does not exist', path);
    final canonical = folder.resolveSymbolicLinksSync();
    final isFlutter = await _isFlutter(canonical);
    final now = DateTime.now();
    await _database
        .into(_database.projectsTable)
        .insert(
          ProjectsTableCompanion.insert(
            path: canonical,
            name: p.basename(canonical),
            isFlutter: Value<bool>(isFlutter),
            lastOpenedAt: Value<DateTime>(now),
          ),
          onConflict: DoUpdate<$ProjectsTableTable, ProjectRow>(
            (_) => ProjectsTableCompanion(
              isFlutter: Value<bool>(isFlutter),
              lastOpenedAt: Value<DateTime>(now),
            ),
            target: <Column<Object>>[_database.projectsTable.path],
          ),
        );
    final row = await (_database.select(
      _database.projectsTable,
    )..where((p) => p.path.equals(canonical))).getSingle();
    return Project.fromRow(row);
  }

  /// A `pubspec.yaml` whose dependencies include `flutter:` (the SDK entry).
  static Future<bool> _isFlutter(String folder) async {
    final pubspec = io.File(p.join(folder, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return false;
    return _flutterDependency.hasMatch(await pubspec.readAsString());
  }
}
