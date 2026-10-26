import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/data/prompt_sending_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'prompt_sending_controller.freezed.dart';

@freezed
sealed class PromptSendingState with _$PromptSendingState {
  const factory PromptSendingState.initial() = PromptSending$InitialState;

  /// A turn is running; another send is dropped.
  const factory PromptSendingState.inProgress() = PromptSending$InProgressState;

  const factory PromptSendingState.error({Object? error}) = PromptSending$ErrorState;

  const factory PromptSendingState.completed() = PromptSending$CompletedState;
}

/// Sends prompts. Stop is not a handled operation: it must run while the
/// send of the same turn is still in progress.
final class PromptSendingController extends StateController<PromptSendingState>
    with DroppableControllerHandler {
  PromptSendingController({
    required this._repository,
    super.initialState = const PromptSendingState.initial(),
  });

  final IPromptSendingRepository _repository;

  void send(
    int sessionId,
    String text, {
    List<Map<String, Object?>> resources = const <Map<String, Object?>>[],
  }) => handle(() async {
    setState(const PromptSendingState.inProgress());
    await _repository.send(sessionId, text, resources: resources);
    setState(const PromptSendingState.completed());
  }, error: (error, stackTrace) async => setState(PromptSendingState.error(error: error)));

  void repeat(int sessionId) => handle(() async {
    setState(const PromptSendingState.inProgress());
    await _repository.repeat(sessionId);
    setState(const PromptSendingState.completed());
  }, error: (error, stackTrace) async => setState(PromptSendingState.error(error: error)));

  /// Control lane: runs immediately, even while [send] waits for the turn.
  Future<void> stop(int sessionId) => _repository.stop(sessionId);

  /// Control lane: kills the agent process.
  Future<void> forceStop(String agentId) => _repository.forceStop(agentId);
}
