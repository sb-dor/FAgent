import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/projects/data/projects_repository.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'projects_controller.freezed.dart';

@freezed
sealed class ProjectsState with _$ProjectsState {
  const factory ProjectsState.initial() = Projects$InitialState;

  const factory ProjectsState.inProgress() = Projects$InProgressState;

  const factory ProjectsState.error({Object? error}) = Projects$ErrorState;

  const factory ProjectsState.completed(List<Project> projects) = Projects$CompletedState;
}

/// Keeps the sidebar's project list in sync with the database.
final class ProjectsController extends StateController<ProjectsState>
    with SequentialControllerHandler {
  ProjectsController({
    required this._repository,
    super.initialState = const ProjectsState.initial(),
  });

  final IProjectsRepository _repository;
  StreamSubscription<List<Project>>? _subscription;

  void watch() => handle(() async {
    setState(const ProjectsState.inProgress());
    await _subscription?.cancel();
    _subscription = _repository.watchProjects().listen(
      (projects) => setState(ProjectsState.completed(projects)),
      onError: (Object error) => setState(ProjectsState.error(error: error)),
    );
  }, error: (error, stackTrace) async => setState(ProjectsState.error(error: error)));

  /// Shows [path] in Finder. Throws when it cannot.
  Future<void> reveal(String path) => _repository.reveal(path);

  /// Opens [path] with the system's application for it. Throws when it cannot.
  Future<void> openPath(String path) => _repository.openPath(path);

  @override
  void dispose() {
    _subscription?.cancel().ignore();
    super.dispose();
  }
}
