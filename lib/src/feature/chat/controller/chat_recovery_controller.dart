import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/chat/data/chat_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_recovery_controller.freezed.dart';

@freezed
sealed class ChatRecoveryState with _$ChatRecoveryState {
  const factory ChatRecoveryState.initial() = ChatRecovery$InitialState;

  const factory ChatRecoveryState.inProgress() = ChatRecovery$InProgressState;

  const factory ChatRecoveryState.error({Object? error}) = ChatRecovery$ErrorState;

  const factory ChatRecoveryState.completed() = ChatRecovery$CompletedState;
}

/// Recovery actions offered by the problem banner. The chat's status shows
/// the outcome; this controller only guards against double clicks.
final class ChatRecoveryController extends StateController<ChatRecoveryState>
    with DroppableControllerHandler {
  ChatRecoveryController({
    required this._repository,
    super.initialState = const ChatRecoveryState.initial(),
  });

  final IChatRepository _repository;

  void retry(int sessionId) => handle(() async {
    setState(const ChatRecoveryState.inProgress());
    await _repository.retry(sessionId);
    setState(const ChatRecoveryState.completed());
  }, error: (error, stackTrace) async => setState(ChatRecoveryState.error(error: error)));

  void login(String agentId) => handle(() async {
    setState(const ChatRecoveryState.inProgress());
    if (await _repository.login(agentId)) {
      setState(const ChatRecoveryState.completed());
    } else {
      setState(const ChatRecoveryState.error());
    }
  }, error: (error, stackTrace) async => setState(ChatRecoveryState.error(error: error)));

  void startNewAgentSession(int sessionId) => handle(() async {
    setState(const ChatRecoveryState.inProgress());
    await _repository.startNewAgentSession(sessionId);
    setState(const ChatRecoveryState.completed());
  }, error: (error, stackTrace) async => setState(ChatRecoveryState.error(error: error)));
}
