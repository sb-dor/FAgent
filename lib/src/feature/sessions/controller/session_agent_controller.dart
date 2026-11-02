import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/sessions/data/sessions_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'session_agent_controller.freezed.dart';

@freezed
sealed class SessionAgentState with _$SessionAgentState {
  const factory SessionAgentState.initial() = SessionAgent$InitialState;

  const factory SessionAgentState.inProgress() = SessionAgent$InProgressState;

  const factory SessionAgentState.error({Object? error}) = SessionAgent$ErrorState;

  /// The agent of chat [sessionId] is now [agentId]; the chat has to be opened again.
  const factory SessionAgentState.completed({required int sessionId, required String agentId}) =
      SessionAgent$CompletedState;
}

/// Changes the agent of a chat that has not started yet.
final class SessionAgentController extends StateController<SessionAgentState>
    with DroppableControllerHandler {
  SessionAgentController({
    required this._repository,
    super.initialState = const SessionAgentState.initial(),
  });

  final ISessionsRepository _repository;

  /// Makes [agentId] run chat [sessionId].
  void set(int sessionId, String agentId) => handle(() async {
    setState(const SessionAgentState.inProgress());
    await _repository.setAgent(sessionId, agentId);
    setState(SessionAgentState.completed(sessionId: sessionId, agentId: agentId));
  }, error: (error, stackTrace) async => setState(SessionAgentState.error(error: error)));
}
