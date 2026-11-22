import 'package:flutter_code_agent/src/feature/project_creation/models/new_member_request.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'creation_step.freezed.dart';

/// One stage of creating a project.
enum CreationStepKind {
  /// The workspace root of a monorepo: its `pubspec.yaml`, `.gitignore` and scripts.
  workspace,

  /// `flutter create` or `dart create` of a member added to a monorepo.
  memberCreate,

  /// `pub get` at the workspace root.
  pubGet,

  /// The commit that adds a member to a monorepo.
  commit,

  /// `flutter create`.
  flutterCreate,

  /// `git init`.
  gitInit,

  /// The architecture skeleton: the template files and their packages.
  skeleton,

  /// `flutter analyze`.
  analyze,

  /// The app's rules: `docs/rules`, `AGENTS.md` and `CLAUDE.md`.
  rules,

  /// The first commit.
  firstCommit,
}

/// Where a [CreationStep] is.
enum CreationStepStatus {
  /// Not started.
  pending,

  /// Running now.
  running,

  /// Finished.
  done,

  /// Stopped with an error.
  failed,
}

/// A stage of creating a project, as the progress screen shows it.
@freezed
abstract class CreationStep with _$CreationStep {
  /// Creates a step.
  const factory CreationStep({
    required CreationStepKind kind,
    @Default(CreationStepStatus.pending) CreationStepStatus status,

    /// The lines under the step, in monospace.
    @Default(<String>[]) List<String> output,

    /// How long the step took; `null` until it is done.
    Duration? took,
  }) = _CreationStep;
}

/// Something a finished creation tells the user to do next.
enum CreationNote {
  /// A Crashlytics project needs `flutterfire configure` to connect Firebase; until then its
  /// errors stay in the log.
  flutterfireConfigure,
}

/// A snapshot of a creation: all its steps as of now, and the [notes] for the user so far.
@freezed
abstract class CreationRun with _$CreationRun {
  /// Creates a snapshot.
  const factory CreationRun({
    required List<CreationStep> steps,
    @Default(<CreationNote>[]) List<CreationNote> notes,
  }) = _CreationRun;
}

/// A creation whose steps ended with the step [kind] failed.
final class CreationStepFailed implements Exception {
  /// Creates the error.
  const CreationStepFailed(this.kind);

  /// The step that failed.
  final CreationStepKind kind;

  @override
  String toString() => 'CreationStepFailed(${kind.name})';
}

/// A creation whose stream ended before every step was done, for example because the repository was
/// disposed while it ran.
final class CreationInterrupted implements Exception {
  /// Creates the error.
  const CreationInterrupted();

  @override
  String toString() => 'CreationInterrupted';
}

/// The stages [request] goes through, in order.
List<CreationStepKind> creationStepsFor(NewProjectRequest request) => <CreationStepKind>[
  if (request.monorepo) CreationStepKind.workspace,
  CreationStepKind.flutterCreate,
  if (request.gitInit) CreationStepKind.gitInit,
  if (request.skeleton)
    CreationStepKind.skeleton
  else if (request.monorepo)
    CreationStepKind.pubGet,
  CreationStepKind.analyze,
  CreationStepKind.rules,
  if (request.gitInit) CreationStepKind.firstCommit,
];

/// The stages adding [request] to a monorepo goes through, in order.
List<CreationStepKind> memberStepsFor(NewMemberRequest request) => <CreationStepKind>[
  CreationStepKind.memberCreate,
  if (request.skeleton) CreationStepKind.skeleton else CreationStepKind.pubGet,
  if (request.gitRepo) CreationStepKind.commit,
  CreationStepKind.analyze,
];

/// The oldest Dart that has pub workspaces the way FAgent builds them.
const String kMonorepoMinDart = '3.14';

/// Whether a Flutter SDK with [dartVersion] (for example `3.14.0`) can make a monorepo.
bool supportsMonorepo(String? dartVersion) => _atLeast(dartVersion, kMonorepoMinDart);

/// The oldest Flutter "My architecture" is made for: its template imports `material_ui` and
/// `cupertino_ui`, which need it.
const String kArchitectureMinFlutter = '3.50';

/// Whether a Flutter SDK of [flutterVersion] (for example `3.50.0` or `3.50.0-0.1.pre`) can make
/// the architecture skeleton; `false` when the version is unknown.
bool supportsArchitecture(String? flutterVersion) =>
    _atLeast(flutterVersion, kArchitectureMinFlutter);

/// Whether [version] (`major.minor` first, anything after it ignored) is [min] (`major.minor`) or
/// newer; `false` for `null` or a version that does not start that way.
bool _atLeast(String? version, String min) {
  final match = RegExp(r'^(\d+)\.(\d+)').firstMatch(version ?? '');
  if (match == null) {
    return false;
  }
  final [minMajor, minMinor] = min.split('.').map(int.parse).toList();
  final major = int.parse(match[1]!);
  final minor = int.parse(match[2]!);
  return major != minMajor ? major > minMajor : minor >= minMinor;
}
