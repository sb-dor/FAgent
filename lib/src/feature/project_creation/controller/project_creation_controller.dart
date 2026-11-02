import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'project_creation_controller.freezed.dart';

@freezed
sealed class ProjectCreationState with _$ProjectCreationState {
  /// Nothing is being created.
  const factory ProjectCreationState.idle() = ProjectCreation$IdleState;

  /// The project of [request] is being created; [steps] are all its stages as of now.
  const factory ProjectCreationState.running({
    required NewProjectRequest request,
    required List<CreationStep> steps,
  }) = ProjectCreation$RunningState;

  /// The project of [request] was created; [projectId] is its id in the app's database.
  const factory ProjectCreationState.completed({
    required NewProjectRequest request,
    required List<CreationStep> steps,
    int? projectId,
  }) = ProjectCreation$CompletedState;

  /// Creating the project of [request] failed with [error]; [steps] are the stages as they were.
  /// [projectId] is set if the project was already registered.
  const factory ProjectCreationState.failed({
    required NewProjectRequest request,
    required List<CreationStep> steps,
    required Object error,
    int? projectId,
  }) = ProjectCreation$FailedState;
}

/// Creates a new Flutter project, one at a time.
///
/// It lives as long as the window, so closing the dialog does not stop a creation. A start during
/// another creation, or before [reset] of a finished one, is dropped.
final class ProjectCreationController extends StateController<ProjectCreationState>
    with DroppableControllerHandler {
  ProjectCreationController({
    required this._repository,
    super.initialState = const ProjectCreationState.idle(),
  });

  final IProjectCreationRepository _repository;

  StreamSubscription<CreationRun>? _subscription;
  Completer<void>? _finished;

  /// The folder to suggest as the parent of a new project.
  Future<String> defaultParent() => _repository.defaultParent();

  /// Whether `<parent>/<name>` can be created; `null` when it can.
  Future<TargetProblem?> checkTarget(String parent, String name) =>
      _repository.checkTarget(parent, name);

  /// Creates the project of [request]. Does nothing unless the controller is idle.
  void start(NewProjectRequest request) => handle(() async {
    if (state is! ProjectCreation$IdleState) return;
    var steps = <CreationStep>[
      for (final kind in creationStepsFor(request)) CreationStep(kind: kind),
    ];
    setState(ProjectCreationState.running(request: request, steps: steps));
    final finished = _finished = Completer<void>();
    int? projectId;
    Object? failure;
    _subscription = _repository
        .create(request)
        .listen(
          (snapshot) {
            steps = snapshot.steps;
            projectId = snapshot.projectId ?? projectId;
            if (!isDisposed) {
              setState(ProjectCreationState.running(request: request, steps: steps));
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
    // A stream that ends normally with a failed step is a failed creation too.
    final failedStep = steps.where((step) => step.status == CreationStepStatus.failed).firstOrNull;
    final error = failure ?? (failedStep == null ? null : CreationStepFailed(failedStep.kind));
    setState(
      error == null
          ? ProjectCreationState.completed(request: request, steps: steps, projectId: projectId)
          : ProjectCreationState.failed(
              request: request,
              steps: steps,
              error: error,
              projectId: projectId,
            ),
    );
  }, error: (error, stackTrace) async => _failWith(error));

  /// Kills the command that is running now; the creation then ends as failed. Does nothing unless
  /// a creation is running.
  void stop() {
    if (state is ProjectCreation$RunningState) _repository.stop().ignore();
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
      case ProjectCreation$RunningState(:final request, :final steps):
        setState(ProjectCreationState.failed(request: request, steps: steps, error: error));
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
