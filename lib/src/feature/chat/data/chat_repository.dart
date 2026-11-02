import 'package:dart_acp_sdk/dart_acp_sdk.dart' show CancellationException;
import 'package:flutter_code_agent/src/common/acp/agent_auth.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agents_repository.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';

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

  /// The sign-in methods of every agent by agent id: the last known at once, then again whenever
  /// an agent is checked. Cancel the subscription to stop watching.
  Stream<Map<String, List<AgentLoginMethod>>> watchLoginMethods();

  /// Stops the running browser or key sign-in of [agentId]; the pending [login] returns `false`.
  Future<void> cancelLogin(String agentId);

  /// Signs [agentId] in with [methodId]; `true` on success, `false` when it
  /// failed or was cancelled. [onOutput] gets a terminal login's output lines
  /// (bounded) as they come; a browser or key sign-in has none. Chats waiting
  /// for the sign-in continue by themselves.
  Future<bool> login(
    String agentId,
    String methodId, {
    required void Function(List<String> lines) onOutput,
  });
}

/// AgentHub-backed [IChatRepository]; sign-in goes through the agents
/// repository, which knows each agent's methods.
final class ChatRepositoryImpl implements IChatRepository {
  /// Creates the repository.
  ChatRepositoryImpl({required this._hub, required this._agents});

  final AgentHub _hub;
  final IAgentsRepository _agents;

  @override
  Future<LiveSession> open(int sessionId) => _hub.session(sessionId);

  @override
  Set<String> openPermissionIds(int sessionId) => _hub.permissions.pendingFor(sessionId).toSet();

  @override
  Future<void> retry(int sessionId) => _hub.retry(sessionId);

  @override
  Future<void> startNewAgentSession(int sessionId) => _hub.startNewAgentSession(sessionId);

  @override
  Stream<Map<String, List<AgentLoginMethod>>> watchLoginMethods() => _agents.watchAgents().map(
    (agents) => <String, List<AgentLoginMethod>>{
      for (final agent in agents) agent.id: agent.methods,
    },
  );

  @override
  Future<void> cancelLogin(String agentId) => _agents.cancelLogin(agentId);

  @override
  Future<bool> login(
    String agentId,
    String methodId, {
    required void Function(List<String> lines) onOutput,
  }) async {
    final AgentLogin? login;
    try {
      login = await _agents.login(agentId, methodId);
    } on CancellationException {
      return false;
    }
    // A browser or key sign-in has ended successfully.
    if (login == null) return true;
    final terminal = login;
    void listener() => onOutput(terminal.output.value);
    terminal.output.addListener(listener);
    listener();
    try {
      return await terminal.succeeded;
    } finally {
      terminal.output.removeListener(listener);
    }
  }
}
