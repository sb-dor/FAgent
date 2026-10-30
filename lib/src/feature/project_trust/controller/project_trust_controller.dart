import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/project_trust/data/project_trust_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'project_trust_controller.freezed.dart';

@freezed
sealed class ProjectTrustState with _$ProjectTrustState {
  const factory ProjectTrustState.initial() = ProjectTrust$InitialState;

  const factory ProjectTrustState.inProgress() = ProjectTrust$InProgressState;

  const factory ProjectTrustState.error({Object? error}) = ProjectTrust$ErrorState;

  /// Settings files found in the folder; the dialog lists them.
  const factory ProjectTrustState.loaded(List<String> settingsFiles) = ProjectTrust$LoadedState;

  const factory ProjectTrustState.completed() = ProjectTrust$CompletedState;
}

/// Asks for and records trust in a project folder.
final class ProjectTrustController extends StateController<ProjectTrustState>
    with DroppableControllerHandler {
  ProjectTrustController({
    required this._repository,
    super.initialState = const ProjectTrustState.initial(),
  });

  final IProjectTrustRepository _repository;

  void inspect(String projectPath) => handle(() async {
    setState(const ProjectTrustState.inProgress());
    setState(ProjectTrustState.loaded(await _repository.agentSettingsFiles(projectPath)));
  }, error: (error, stackTrace) async => setState(ProjectTrustState.error(error: error)));

  void trust(int projectId) => handle(() async {
    setState(const ProjectTrustState.inProgress());
    await _repository.trust(projectId);
    setState(const ProjectTrustState.completed());
  }, error: (error, stackTrace) async => setState(ProjectTrustState.error(error: error)));
}
