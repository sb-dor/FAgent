import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'creation_step.freezed.dart';

/// One stage of creating a project.
enum CreationStepKind {
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

/// A snapshot of a creation: all its steps as of now and the project, once it is registered.
@freezed
abstract class CreationRun with _$CreationRun {
  /// Creates a snapshot.
  const factory CreationRun({
    required List<CreationStep> steps,

    /// The id of the project in the app's database; `null` until the project is registered.
    int? projectId,
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
  CreationStepKind.flutterCreate,
  if (request.gitInit) CreationStepKind.gitInit,
  if (request.template == NewProjectTemplate.architecture) CreationStepKind.skeleton,
  CreationStepKind.analyze,
  CreationStepKind.rules,
  if (request.gitInit) CreationStepKind.firstCommit,
];
