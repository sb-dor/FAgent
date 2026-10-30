import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/session_creation/data/session_creation_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'session_creation_controller.freezed.dart';

@freezed
sealed class SessionCreationState with _$SessionCreationState {
  const factory SessionCreationState.initial() = SessionCreation$InitialState;

  const factory SessionCreationState.inProgress() = SessionCreation$InProgressState;

  const factory SessionCreationState.error({Object? error}) = SessionCreation$ErrorState;

  const factory SessionCreationState.completed(int sessionId) = SessionCreation$CompletedState;
}

/// Creates a new chat in a project.
final class SessionCreationController extends StateController<SessionCreationState>
    with DroppableControllerHandler {
  SessionCreationController({
    required this._repository,
    super.initialState = const SessionCreationState.initial(),
  });

  final ISessionCreationRepository _repository;

  void create({required int projectId, required String agentId}) => handle(() async {
    setState(const SessionCreationState.inProgress());
    final id = await _repository.create(projectId: projectId, agentId: agentId);
    setState(SessionCreationState.completed(id));
  }, error: (error, stackTrace) async => setState(SessionCreationState.error(error: error)));
}
