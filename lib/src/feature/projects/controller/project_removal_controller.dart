import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/projects/data/projects_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'project_removal_controller.freezed.dart';

@freezed
sealed class ProjectRemovalState with _$ProjectRemovalState {
  const factory ProjectRemovalState.initial() = ProjectRemoval$InitialState;

  const factory ProjectRemovalState.inProgress() = ProjectRemoval$InProgressState;

  /// An agent works in a chat of the project; nothing was removed.
  const factory ProjectRemovalState.busy() = ProjectRemoval$BusyState;

  const factory ProjectRemovalState.error({Object? error}) = ProjectRemoval$ErrorState;

  const factory ProjectRemovalState.completed(int projectId) = ProjectRemoval$CompletedState;
}

/// Forgets a project with its chats. The sidebar's list updates through `ProjectsController`.
final class ProjectRemovalController extends StateController<ProjectRemovalState>
    with DroppableControllerHandler {
  ProjectRemovalController({
    required this._repository,
    super.initialState = const ProjectRemovalState.initial(),
  });

  final IProjectsRepository _repository;

  void remove(int projectId) => handle(() async {
    setState(const ProjectRemovalState.inProgress());
    try {
      await _repository.remove(projectId);
    } on ProjectBusyException {
      setState(const ProjectRemovalState.busy());
      return;
    }
    setState(ProjectRemovalState.completed(projectId));
  }, error: (error, stackTrace) async => setState(ProjectRemovalState.error(error: error)));
}
