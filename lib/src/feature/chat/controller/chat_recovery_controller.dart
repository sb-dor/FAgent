import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/chat/data/chat_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_recovery_controller.freezed.dart';

@freezed
sealed class ChatRecoveryState with _$ChatRecoveryState {
  const factory ChatRecoveryState.initial() = ChatRecovery$InitialState;

  /// [output]: lines of a running login.
  const factory ChatRecoveryState.inProgress({@Default(<String>[]) List<String> output}) =
      ChatRecovery$InProgressState;

  /// [output]: lines of the failed login, for the user to read.
  const factory ChatRecoveryState.error({Object? error, @Default(<String>[]) List<String> output}) =
      ChatRecovery$ErrorState;

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

  /// Login methods of [agentId].
  List<String> loginMethods(String agentId) => _repository.loginMethods(agentId);

  void login(String agentId, String methodId) {
    var output = const <String>[];
    handle(
      () async {
        setState(const ChatRecoveryState.inProgress());
        final succeeded = await _repository.login(
          agentId,
          methodId,
          onOutput: (lines) {
            output = lines;
            if (!isDisposed) setState(ChatRecoveryState.inProgress(output: lines));
          },
        );
        setState(
          succeeded ? const ChatRecoveryState.completed() : ChatRecoveryState.error(output: output),
        );
      },
      error: (error, stackTrace) async =>
          setState(ChatRecoveryState.error(error: error, output: output)),
    );
  }

  void startNewAgentSession(int sessionId) => handle(() async {
    setState(const ChatRecoveryState.inProgress());
    await _repository.startNewAgentSession(sessionId);
    setState(const ChatRecoveryState.completed());
  }, error: (error, stackTrace) async => setState(ChatRecoveryState.error(error: error)));
}
