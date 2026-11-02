import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';

/// Why `<parent>/<name>` cannot be created.
enum TargetProblem {
  /// Something is already at `<parent>/<name>`: a folder (even an empty one) or a file.
  exists,

  /// The parent folder is not on disk.
  parentMissing,
}

/// Creates new Flutter projects.
abstract interface class IProjectCreationRepository {
  /// Whether [create] only pretends (until milestone M4).
  bool get isPreview;

  /// The folder to suggest as the parent: the one the last opened project is in, if it is on
  /// disk; else `~/StudioProjects`, if it exists; else the home folder.
  Future<String> defaultParent();

  /// Whether `<parent>/<name>` can be created; `null` when it can.
  Future<TargetProblem?> checkTarget(String parent, String name);

  /// Creates the project of [request]. Emits the snapshot of the run whenever a step changes and
  /// closes after the last step. Cancel the subscription to stop listening.
  Stream<CreationRun> create(NewProjectRequest request);

  /// Kills the command that is running now. The stream of [create] then ends as a failure: the
  /// step that was running is `failed`.
  Future<void> stop();

  /// Kills whatever is still running and releases the repository.
  Future<void> dispose();
}
