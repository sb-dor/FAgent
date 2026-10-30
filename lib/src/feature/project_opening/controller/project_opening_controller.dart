import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/project_opening/data/project_opening_repository.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'project_opening_controller.freezed.dart';

@freezed
sealed class ProjectOpeningState with _$ProjectOpeningState {
  const factory ProjectOpeningState.initial() = ProjectOpening$InitialState;

  const factory ProjectOpeningState.inProgress() = ProjectOpening$InProgressState;

  const factory ProjectOpeningState.error({Object? error}) = ProjectOpening$ErrorState;

  const factory ProjectOpeningState.completed(Project project) = ProjectOpening$CompletedState;
}

/// Opens a folder as a project.
final class ProjectOpeningController extends StateController<ProjectOpeningState>
    with DroppableControllerHandler {
  ProjectOpeningController({
    required this._repository,
    super.initialState = const ProjectOpeningState.initial(),
  });

  final IProjectOpeningRepository _repository;

  void open(String path) => handle(() async {
    setState(const ProjectOpeningState.inProgress());
    setState(ProjectOpeningState.completed(await _repository.open(path)));
  }, error: (error, stackTrace) async => setState(ProjectOpeningState.error(error: error)));
}
