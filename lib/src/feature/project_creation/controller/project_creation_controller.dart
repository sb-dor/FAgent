import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter_code_agent/src/common/utils/error_util.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_member_request.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:flutter_code_agent/src/feature/project_opening/data/project_opening_repository.dart';
import 'package:flutter_code_agent/src/feature/project_rules/data/project_rules_repository.dart';
import 'package:flutter_code_agent/src/feature/project_trust/data/project_trust_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'project_creation_controller.freezed.dart';

@freezed
sealed class ProjectCreationState with _$ProjectCreationState {
  /// Nothing is being created.
  const factory ProjectCreationState.idle() = ProjectCreation$IdleState;

  /// A project ([request]) is being created, or a member ([member]) is being added to one; exactly
  /// one of the two is set. [steps] are all its stages as of now. [stopping] is set once a stop was
  /// asked for and the run has not ended yet.
  const factory ProjectCreationState.running({
    NewProjectRequest? request,
    NewMemberRequest? member,
    required List<CreationStep> steps,
    @Default(false) bool stopping,
  }) = ProjectCreation$RunningState;

  /// The project of [request] was created ([projectId] is its id in the app's database), or the
  /// member was added. [notes] are the scripts of an added member's project that list its members
  /// and may need an edit; empty for a created project.
  const factory ProjectCreationState.completed({
    NewProjectRequest? request,
    NewMemberRequest? member,
    required List<CreationStep> steps,
    int? projectId,
    @Default(<String>[]) List<String> notes,
  }) = ProjectCreation$CompletedState;

  /// Creating the project of [request] (or adding [member]) failed with [error]; [steps] are the
  /// stages as they were. [projectId] is set if the project was already registered.
  const factory ProjectCreationState.failed({
    NewProjectRequest? request,
    NewMemberRequest? member,
    required List<CreationStep> steps,
    required Object error,
    int? projectId,
  }) = ProjectCreation$FailedState;
}

/// Creates a new Flutter project or adds a member to a monorepo, one run at a time.
///
/// Once the creation's steps are over and `flutter create` is done (even if a later step failed or
/// was stopped), it adds the project to the app, trusts it and marks its rules as offered.
///
/// It lives as long as the window, so closing the dialog does not stop a creation. A start during
/// another run, or before [reset] of a finished one, is dropped.
final class ProjectCreationController extends StateController<ProjectCreationState>
    with DroppableControllerHandler {
  ProjectCreationController({
    required this._repository,
    required this._projectOpening,
    required this._projectTrust,
    required this._projectRules,
    super.initialState = const ProjectCreationState.idle(),
  });

  final IProjectCreationRepository _repository;
  final IProjectOpeningRepository _projectOpening;
  final IProjectTrustRepository _projectTrust;
  final IProjectRulesRepository _projectRules;

  StreamSubscription<CreationRun>? _subscription;
  Completer<void>? _finished;

  /// The folder to suggest as the parent of a new project.
  Future<String> defaultParent() => _repository.defaultParent();

  /// Whether `<parent>/<name>` can be created; `null` when it can.
  Future<TargetProblem?> checkTarget(String parent, String name) =>
      _repository.checkTarget(parent, name);

  /// Whether the member [folder] of [kind] with [packageName] can be added to [projectPath]; `null`
  /// when it can.
  Future<MemberProblem?> checkMember(
    String projectPath,
    MemberKind kind,
    String folder,
    String packageName,
  ) => _repository.checkMember(projectPath, kind, folder, packageName);

  /// The package name to suggest for a member in [folder].
  Future<String> suggestedPackageName(String projectPath, String folder) =>
      _repository.suggestedPackageName(projectPath, folder);

  /// Whether the monorepo has a `packages/ui` package.
  Future<bool> hasUiPackage(String projectPath) => _repository.hasUiPackage(projectPath);

  /// Whether the project is a git repository.
  Future<bool> isGitRepo(String projectPath) => _repository.isGitRepo(projectPath);

  /// Creates the project of [request]. Does nothing unless the controller is idle.
  void start(NewProjectRequest request) => _run(
    stepKinds: creationStepsFor(request),
    stream: () => _repository.create(request),
    running: (steps, {required stopping}) =>
        ProjectCreationState.running(request: request, steps: steps, stopping: stopping),
    completed: (steps, projectId, notes) =>
        ProjectCreationState.completed(request: request, steps: steps, projectId: projectId),
    failed: (steps, error, projectId) => ProjectCreationState.failed(
      request: request,
      steps: steps,
      error: error,
      projectId: projectId,
    ),
    register: () async {
      final project = await _projectOpening.open(request.path);
      if (isDisposed) return null;
      await _projectTrust.trust(project.id);
      // It has the rules (or the user turned them all off): the app does not offer them again.
      await _projectRules.markOffered(project.id);
      return project.id;
    },
    afterSuccess: () async => const <String>[],
  );

  /// Adds the member of [request] to its project. Does nothing unless the controller is idle.
  ///
  /// It goes through the same states as [start] but registers no project; the completed state
  /// carries the scripts that list the project's members as `notes`.
  void startAdd(NewMemberRequest request) => _run(
    stepKinds: memberStepsFor(request),
    stream: () => _repository.addMember(request),
    running: (steps, {required stopping}) =>
        ProjectCreationState.running(member: request, steps: steps, stopping: stopping),
    completed: (steps, projectId, notes) =>
        ProjectCreationState.completed(member: request, steps: steps, notes: notes),
    failed: (steps, error, projectId) =>
        ProjectCreationState.failed(member: request, steps: steps, error: error),
    afterSuccess: () async {
      try {
        return await _repository.scriptsListingMembers(request.projectPath);
      } on Object catch (error, stackTrace) {
        // The notes are advice only; the member is added either way.
        ErrorUtil.logError(error, stackTrace).ignore();
        return const <String>[];
      }
    },
  );

  /// Runs [stream] through the running, completed and failed states built by the callbacks.
  ///
  /// [register] runs once the first step is done and the run was not interrupted, and returns the
  /// id of the registered project (only a created project registers). [afterSuccess] gives the
  /// notes of a run that ended without error.
  void _run({
    required List<CreationStepKind> stepKinds,
    required Stream<CreationRun> Function() stream,
    required ProjectCreationState Function(List<CreationStep> steps, {required bool stopping})
    running,
    required ProjectCreationState Function(
      List<CreationStep> steps,
      int? projectId,
      List<String> notes,
    )
    completed,
    required ProjectCreationState Function(List<CreationStep> steps, Object error, int? projectId)
    failed,
    Future<int?> Function()? register,
    required Future<List<String>> Function() afterSuccess,
  }) => handle(() async {
    if (state is! ProjectCreation$IdleState) return;
    var steps = <CreationStep>[for (final kind in stepKinds) CreationStep(kind: kind)];
    setState(running(steps, stopping: false));
    final finished = _finished = Completer<void>();
    int? projectId;
    Object? failure;
    _subscription = stream().listen(
      (snapshot) {
        steps = snapshot.steps;
        if (!isDisposed) {
          final current = state;
          setState(
            running(steps, stopping: current is ProjectCreation$RunningState && current.stopping),
          );
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        failure = error;
        if (!finished.isCompleted) finished.complete();
      },
      onDone: () {
        if (!finished.isCompleted) finished.complete();
      },
      cancelOnError: true,
    );
    await finished.future;
    _subscription = null;
    if (isDisposed) return;
    // A stream that ends normally with a failed step is a failed run too, and so is one that
    // ends before every step is done (for example when the repository is disposed at quit).
    final failedStep = steps.where((step) => step.status == CreationStepStatus.failed).firstOrNull;
    final error =
        failure ??
        (failedStep != null
            ? CreationStepFailed(failedStep.kind)
            : (steps.every((step) => step.status == CreationStepStatus.done)
                  ? null
                  : const CreationInterrupted()));
    // The project is there once `flutter create` is done, even if a later step failed or was
    // stopped. An interrupted run (the repository disposed) adds nothing.
    if (register != null &&
        error is! CreationInterrupted &&
        failure == null &&
        steps.first.status == CreationStepStatus.done) {
      try {
        projectId = await register();
      } on Object catch (addError) {
        if (!isDisposed) setState(failed(steps, addError, null));
        rethrow;
      }
      if (isDisposed) return;
    }
    final notes = error == null ? await afterSuccess() : const <String>[];
    if (isDisposed) return;
    setState(error == null ? completed(steps, projectId, notes) : failed(steps, error, projectId));
  }, error: (error, stackTrace) async => _failWith(error));

  /// Kills the command that is running now; the creation then ends as failed. Does nothing unless
  /// a creation is running, and a second call while it is stopping does nothing too.
  void stop() {
    final current = state;
    if (current is! ProjectCreation$RunningState || current.stopping) return;
    setState(
      ProjectCreationState.running(
        request: current.request,
        member: current.member,
        steps: current.steps,
        stopping: true,
      ),
    );
    _repository.stop().ignore();
  }

  /// Goes from a finished (completed or failed) creation back to idle; does nothing otherwise.
  void reset() {
    if (state is ProjectCreation$CompletedState || state is ProjectCreation$FailedState) {
      setState(const ProjectCreationState.idle());
    }
  }

  void _failWith(Object error) {
    if (isDisposed) return;
    switch (state) {
      case ProjectCreation$RunningState(:final request, :final member, :final steps):
        setState(
          ProjectCreationState.failed(request: request, member: member, steps: steps, error: error),
        );
      default:
        break;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel().ignore();
    _subscription = null;
    final finished = _finished;
    if (finished != null && !finished.isCompleted) finished.complete();
    super.dispose();
  }
}
