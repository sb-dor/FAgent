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

  /// The project of [request] was created.
  const factory ProjectCreationState.completed({
    required NewProjectRequest request,
    required List<CreationStep> steps,
  }) = ProjectCreation$CompletedState;

  /// Creating the project of [request] failed with [error]; [steps] are the stages as they were.
  const factory ProjectCreationState.failed({
    required NewProjectRequest request,
    required List<CreationStep> steps,
    required Object error,
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

  StreamSubscription<List<CreationStep>>? _subscription;
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
    Object? failure;
    _subscription = _repository
        .create(request)
        .listen(
          (snapshot) {
            steps = snapshot;
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
    final error = failure;
    setState(
      error == null
          ? ProjectCreationState.completed(request: request, steps: steps)
          : ProjectCreationState.failed(request: request, steps: steps, error: error),
    );
  }, error: (error, stackTrace) async => _failWith(error));

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
