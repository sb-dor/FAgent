import 'package:flutter_code_agent/src/common/acp/agent_connection.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/session_event.dart';

/// Starts an agent; replaced in tests.
typedef AgentConnector = Future<AgentConnection> Function(
  AgentDefinition definition,
  AgentPermissionHandler onPermission,
);

/// Hooks around every turn (the changed-files snapshot uses it).
abstract interface class TurnObserver {
  /// Runs before `session/prompt` is sent; the turn waits for it.
  Future<Object?> beforeTurn(LiveSession session);

  /// Runs after the turn; a non-null result is journaled as a durable
  /// [SessionEventKind.turnFiles] event.
  Future<Map<String, Object?>?> afterTurn(LiveSession session, Object? beforeToken);
}

/// A message for the UI that is not part of any journal (for example a
/// journal write that failed).
final class HubNotice {
  /// Creates a notice.
  const HubNotice(this.sessionId, this.message);

  /// App session it belongs to.
  final int sessionId;

  /// What happened.
  final String message;
}

/// JSON-RPC error code of `authRequired`.
const int kAcpAuthRequiredCode = -32000;

/// JSON-RPC error code of "resource not found" (unknown session on load).
const int kAcpResourceNotFoundCode = -32002;

/// A chat of an agent that is no longer configured cannot start (its problem
/// is [SessionProblemKind.removed]).
final class AgentRemovedException implements Exception {
  /// Creates the exception.
  const AgentRemovedException();

  @override
  String toString() => 'AgentRemovedException: This agent was removed';
}

/// A prompt was not sent: the chat's mode is `bypassPermissions` and the user
/// has not allowed it ([AgentHub.acknowledgeBypass]). The prompt can be
/// repeated afterwards.
final class BypassNotAllowedException implements Exception {
  /// Creates the exception.
  const BypassNotAllowedException();

  @override
  String toString() => 'BypassNotAllowedException: bypassPermissions is not allowed for this chat';
}
