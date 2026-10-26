import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';

/// A chat's runtime state and its recovery actions.
abstract interface class IChatRepository {
  /// Opens chat [sessionId] (its journal and live state).
  Future<LiveSession> open(int sessionId);

  /// Permission request ids still open in this run, for the feed.
  Set<String> openPermissionIds(int sessionId);

  /// Repeats the failed setup or restarts the agent after an error.
  Future<void> retry(int sessionId);

  /// Destructive: a new agent session; the agent loses the chat's context.
  Future<void> startNewAgentSession(int sessionId);
}

/// AgentHub-backed [IChatRepository].
final class ChatRepositoryImpl implements IChatRepository {
  /// Creates the repository.
  ChatRepositoryImpl({required this._hub});

  final AgentHub _hub;

  @override
  Future<LiveSession> open(int sessionId) => _hub.session(sessionId);

  @override
  Set<String> openPermissionIds(int sessionId) => _hub.permissions.pendingFor(sessionId).toSet();

  @override
  Future<void> retry(int sessionId) => _hub.retry(sessionId);

  @override
  Future<void> startNewAgentSession(int sessionId) => _hub.startNewAgentSession(sessionId);
}
