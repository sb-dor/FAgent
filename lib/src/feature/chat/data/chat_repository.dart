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

  /// Logs in to [agentId] with its first login method; `true` on success.
  /// Chats waiting for the login continue by themselves.
  Future<bool> login(String agentId);
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

  @override
  Future<bool> login(String agentId) async {
    final method = _hub.agents.firstWhere((a) => a.id == agentId).loginArguments.keys.first;
    return (await _hub.login(agentId, method)).succeeded;
  }
}
