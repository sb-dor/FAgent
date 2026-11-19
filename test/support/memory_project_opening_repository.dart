import 'package:flutter_code_agent/src/feature/project_opening/data/project_opening_repository.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:path/path.dart' as p;

/// [IProjectOpeningRepository] for tests: no database, no file system. Every path opens as the
/// project [projectId]; the paths go into [opened].
final class MemoryProjectOpeningRepository implements IProjectOpeningRepository {
  /// The id of every project [open] returns.
  int projectId = 1;

  /// The paths [open] was called with.
  final List<String> opened = <String>[];

  @override
  Future<Project> open(String path) async {
    opened.add(path);
    return Project(id: projectId, path: path, name: p.basename(path), isFlutter: true);
  }
}
