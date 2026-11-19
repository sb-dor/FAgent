import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';

/// Changes agent settings of a chat.
abstract interface class ISessionConfigRepository {
  /// Sets [configId] of chat [sessionId] to [value] (a choice value or a bool).
  Future<void> set(int sessionId, String configId, Object value);

  /// Allows `bypassPermissions` for chat [sessionId].
  Future<void> acknowledgeBypass(int sessionId);
}

/// AgentHub-backed [ISessionConfigRepository].
final class SessionConfigRepositoryImpl implements ISessionConfigRepository {
  /// Creates the repository.
  SessionConfigRepositoryImpl({required this._hub});

  final AgentHub _hub;

  @override
  Future<void> set(int sessionId, String configId, Object value) =>
      _hub.setConfigOption(sessionId, configId, value);

  @override
  Future<void> acknowledgeBypass(int sessionId) => _hub.acknowledgeBypass(sessionId);
}
