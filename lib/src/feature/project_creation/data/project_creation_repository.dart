import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_member_request.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';

/// Why `<parent>/<name>` cannot be created.
enum TargetProblem {
  /// Something is already at `<parent>/<name>`: a folder (even an empty one) or a file.
  exists,

  /// The parent folder is not on disk.
  parentMissing,
}

/// Why a member cannot be added to a monorepo as asked.
enum MemberProblem {
  /// Something is already at `<apps|packages>/<folder>`.
  folderExists,

  /// Another member, or the workspace root, has the package name.
  packageTaken,
}

/// Creates new Flutter projects and adds apps and packages to monorepos.
abstract interface class IProjectCreationRepository {
  /// The folder to suggest as the parent: the one the last opened project is in, if it is on
  /// disk; else `~/StudioProjects`, if it exists; else the home folder.
  Future<String> defaultParent();

  /// Whether `<parent>/<name>` can be created; `null` when it can.
  Future<TargetProblem?> checkTarget(String parent, String name);

  /// Creates the project of [request]. Emits the snapshot of the run whenever a step changes
  /// (output lines included) and closes after the last step; a step that fails ends the run, the
  /// later ones stay pending. It does not add the project to the app: the controller does.
  ///
  /// Cancelling the subscription kills the running command and closes the stream: no snapshot is
  /// emitted after that.
  Stream<CreationRun> create(NewProjectRequest request);

  /// Adds the app or package of [request] to its monorepo, with the same stream contract as
  /// [create]; [stop] and [dispose] apply to it.
  ///
  /// When a step before the commit (before `analyze` when there is no commit step) fails, is
  /// stopped, or the run is cancelled, the folder the add created is deleted and the root's
  /// `pubspec.lock` is put back as it was; the failed step's last line says so. A failed `analyze`
  /// undoes nothing.
  Stream<CreationRun> addMember(NewMemberRequest request);

  /// Whether a member of [kind] in [folder] named [packageName] can be added to the monorepo at
  /// [projectPath]; `null` when it can. The package name's syntax is the form's to check.
  Future<MemberProblem?> checkMember(
    String projectPath,
    MemberKind kind,
    String folder,
    String packageName,
  );

  /// The package name to suggest for a member in [folder]: `<project>_<folder>`, where
  /// `<project>` is the root's package name without `_workspace`, or the project's folder name
  /// when the root's name has no such suffix.
  Future<String> suggestedPackageName(String projectPath, String folder);

  /// Whether the monorepo at [projectPath] has `packages/ui`, which the architecture skeleton
  /// depends on.
  Future<bool> hasUiPackage(String projectPath);

  /// Whether the monorepo at [projectPath] has the shared packages the architecture skeleton of an
  /// app depends on: `packages/telemetry`, `packages/database` and `packages/api_client`. A
  /// monorepo made before them has none.
  Future<bool> hasSharedPackages(String projectPath);

  /// Whether a Dart file under `packages/ui/lib` of the monorepo at [projectPath] imports or
  /// exports `package:flutter/material.dart` or `package:flutter/cupertino.dart`: a `packages/ui`
  /// from before `material_ui`, whose widgets would not see the theme of a skeleton on
  /// `material_ui`. `false` without `packages/ui`.
  Future<bool> uiUsesSdkMaterial(String projectPath);

  /// Whether the project at [projectPath] is a git repository.
  Future<bool> isGitRepo(String projectPath);

  /// The files under `scripts/` of the monorepo at [projectPath] that name an existing member by
  /// its folder (`packages/core`), not by a glob: they would miss a new member. Paths are relative
  /// to [projectPath], with `/`, sorted.
  Future<List<String>> scriptsListingMembers(String projectPath);

  /// Kills the command that is running now. That step fails with the last output line `Stopped`,
  /// no later step runs, and the stream of [create] or [addMember] ends normally with that step
  /// failed. Never throws.
  Future<void> stop();

  /// Stops the command that is running and closes the stream of a run in progress with a normal
  /// done: no step is marked failed. An add in progress is rolled back before it returns. Listeners must not read that as success;
  /// the controller treats a run without every step done as interrupted. Releases the repository.
  /// Never throws.
  Future<void> dispose();
}
