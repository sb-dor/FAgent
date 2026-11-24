import 'package:flutter_code_agent/_core/acp/agent_hub.dart';
import 'package:flutter_code_agent/prompt_sending/data/prompt_blocks.dart';
import 'package:flutter_code_agent/prompt_sending/models/prompt_attachment.dart';

/// Sends prompts and stops turns.
abstract interface class IPromptSendingRepository {
  /// Sends [text] with [attachments] (files, images, a skill) to chat [sessionId]; completes
  /// when the turn ends.
  Future<void> send(
    int sessionId,
    String text, {
    List<PromptAttachment> attachments = const <PromptAttachment>[],
  });

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
  Future<void> send(
    int sessionId,
    String text, {
    List<PromptAttachment> attachments = const <PromptAttachment>[],
  }) => _hub.prompt(sessionId, text, resources: promptBlocks(attachments));

  @override
  Future<void> repeat(int sessionId) => _hub.retryPrompt(sessionId);

  @override
  Future<void> stop(int sessionId) => _hub.cancel(sessionId);

  @override
  Future<void> forceStop(String agentId) => _hub.forceStop(agentId);
}
