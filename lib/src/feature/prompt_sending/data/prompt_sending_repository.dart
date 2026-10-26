import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';

/// Sends prompts and stops turns.
abstract interface class IPromptSendingRepository {
  /// Sends [text] to chat [sessionId]; completes when the turn ends.
  Future<void> send(int sessionId, String text);

  /// Repeats the last prompt (after a login).
  Future<void> repeat(int sessionId);

  /// Stops the running turn.
  Future<void> stop(int sessionId);

  /// Kills [agentId]'s process when Stop hangs.
  Future<void> forceStop(String agentId);
}

/// AgentHub-backed [IPromptSendingRepository].
final class PromptSendingRepositoryImpl implements IPromptSendingRepository {
  /// Creates the repository.
  PromptSendingRepositoryImpl({required this._hub});

  final AgentHub _hub;

  @override
  Future<void> send(int sessionId, String text) => _hub.prompt(sessionId, text);

  @override
  Future<void> repeat(int sessionId) => _hub.retryPrompt(sessionId);

  @override
  Future<void> stop(int sessionId) => _hub.cancel(sessionId);

  @override
  Future<void> forceStop(String agentId) => _hub.forceStop(agentId);
}
