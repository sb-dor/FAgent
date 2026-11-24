import 'package:control/control.dart';
import 'package:flutter_code_agent/app_settings/data/app_settings_repository.dart';
import 'package:flutter_code_agent/session_config/data/session_config_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'session_config_controller.freezed.dart';

@freezed
sealed class SessionConfigState with _$SessionConfigState {
  const factory SessionConfigState.initial() = SessionConfig$InitialState;

  const factory SessionConfigState.inProgress() = SessionConfig$InProgressState;

  const factory SessionConfigState.error({Object? error}) = SessionConfig$ErrorState;

  const factory SessionConfigState.completed() = SessionConfig$CompletedState;
}

/// Changes agent settings; the chat shows the agent's answer, so the state
/// only covers the request itself.
final class SessionConfigController extends StateController<SessionConfigState>
    with DroppableControllerHandler {
  SessionConfigController({
    required this._repository,
    required this._settings,
    super.initialState = const SessionConfigState.initial(),
  });

  final ISessionConfigRepository _repository;
  final IAppSettingsRepository _settings;

  /// Sets [configId] to [value]. Choosing `bypassPermissions` is allowed only
  /// after the UI asked the user; the hub then allows bypass for the chat.
  void set(int sessionId, String configId, Object value) => handle(() async {
    setState(const SessionConfigState.inProgress());
    await _repository.set(sessionId, configId, value);
    setState(const SessionConfigState.completed());
  }, error: (error, stackTrace) async => setState(SessionConfigState.error(error: error)));

  /// Makes [values] what new chats of [agentId] start with.
  void saveDefaults(String agentId, Map<String, String> values) => handle(() async {
    setState(const SessionConfigState.inProgress());
    final current = await _settings.watch().first;
    await _settings.update(
      current.copyWith(
        sessionDefaults: <String, Map<String, String>>{...current.sessionDefaults, agentId: values},
      ),
    );
    setState(const SessionConfigState.completed());
  }, error: (error, stackTrace) async => setState(SessionConfigState.error(error: error)));

  /// Allows the bypass mode the chat already has (from the user's settings).
  /// Not a handled operation: a setting change in flight must not drop it.
  Future<void> acknowledgeBypass(int sessionId) => _repository.acknowledgeBypass(sessionId);
}
