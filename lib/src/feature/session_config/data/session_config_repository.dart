import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/feature/app_settings/data/app_settings_repository.dart';

/// Changes agent settings of a chat.
abstract interface class ISessionConfigRepository {
  /// Sets [configId] of chat [sessionId] to [value] (a choice value or a bool).
  Future<void> set(int sessionId, String configId, Object value);

  /// Allows `bypassPermissions` for chat [sessionId].
  Future<void> acknowledgeBypass(int sessionId);

  /// Makes [values] (config id → value) what new chats of [agentId] start with.
  /// `mode: bypassPermissions` is never stored.
  Future<void> saveDefaults(String agentId, Map<String, String> values);
}

/// AgentHub-backed [ISessionConfigRepository].
final class SessionConfigRepositoryImpl implements ISessionConfigRepository {
  /// Creates the repository.
  SessionConfigRepositoryImpl({required this._hub, required this._settings});

  final AgentHub _hub;
  final IAppSettingsRepository _settings;

  @override
  Future<void> set(int sessionId, String configId, Object value) =>
      _hub.setConfigOption(sessionId, configId, value);

  @override
  Future<void> acknowledgeBypass(int sessionId) => _hub.acknowledgeBypass(sessionId);

  @override
  Future<void> saveDefaults(String agentId, Map<String, String> values) async {
    final current = await _settings.watch().first;
    await _settings.update(
      current.copyWith(
        sessionDefaults: <String, Map<String, String>>{...current.sessionDefaults, agentId: values},
      ),
    );
  }
}
