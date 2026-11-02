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

  /// Creates the project of [request]. Emits the snapshot of the run whenever a step changes
  /// (output lines included) and closes after the last step; a step that fails ends the run, the
  /// later ones stay pending. Once the steps are over, if `flutter create` is done, the project is
  /// added and trusted and a last snapshot carries its `projectId`; a failure to add it is an error
  /// of the stream.
  ///
  /// Cancelling the subscription kills the running command and closes the stream: no snapshot is
  /// emitted after that and the project is not added.
  Stream<CreationRun> create(NewProjectRequest request);

  /// Kills the command that is running now. That step fails with the last output line `Stopped`,
  /// no later step runs, and the stream of [create] ends as a failure (the project is still added
  /// if `flutter create` is done). Never throws.
  Future<void> stop();

  /// Kills whatever is still running, as if every subscription to [create] were cancelled, and
  /// releases the repository. Never throws.
  Future<void> dispose();
}
