import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/feature/chat/data/chat_repository.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_runtime.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/slash_command.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';

/// A chat of the test with nothing in it but [status].
ChatRuntime statusRuntime(int sessionId, SessionStatus status) => ChatRuntime(
  sessionId: sessionId,
  agentId: 'claude',
  events: const [],
  openPermissionIds: const <String>{},
  status: status,
  problem: null,
  canForceStop: false,
  canRetryPrompt: false,
  configOptions: const <ConfigOption>[],
  bypassBlocked: false,
  preparingTurn: false,
  commands: const <SlashCommand>[],
);

/// An [IChatRepository] whose chats follow the notifiers [statusOf] gives: [watch] emits the
/// chat's status when it is listened to and on every change.
final class StatusChatRepository implements IChatRepository {
  /// Creates the repository.
  StatusChatRepository(this.statusOf);

  /// The live status of a chat.
  final ValueListenable<SessionStatus> Function(int sessionId) statusOf;

  @override
  Stream<ChatRuntime> watch(int sessionId) {
    final status = statusOf(sessionId);
    final controller = StreamController<ChatRuntime>(sync: true);
    void emit() {
      if (!controller.isClosed) controller.add(statusRuntime(sessionId, status.value));
    }

    controller
      ..onListen = () {
        status.addListener(emit);
        emit();
      }
      ..onCancel = () {
        status.removeListener(emit);
        return controller.close();
      };
    return controller.stream;
  }

  @override
  Stream<SessionStatus> watchStatus(int sessionId) {
    final status = statusOf(sessionId);
    final controller = StreamController<SessionStatus>(sync: true);
    void emit() {
      if (!controller.isClosed) controller.add(status.value);
    }

    controller
      ..onListen = () {
        status.addListener(emit);
        emit();
      }
      ..onCancel = () {
        status.removeListener(emit);
        return controller.close();
      };
    return controller.stream;
  }

  @override
  Future<void> retry(int sessionId) async {}

  @override
  Future<void> startNewAgentSession(int sessionId) async {}
}
