import 'package:control/control.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/acp/agent_auth.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agents_repository.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agents_exceptions.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'agent_actions_controller.freezed.dart';

/// What the buttons of the agent cards have done so far.
@freezed
abstract class AgentActionsState with _$AgentActionsState {
  const factory AgentActionsState({
    /// The output lines of the latest login of each agent (agent id → lines).
    @Default(<String, List<String>>{}) Map<String, List<String>> output,

    /// The milestone that ships the thing the last action asked for, when that is still a preview.
    String? previewMilestone,

    /// The last action failed with this; never an `AgentPreviewException`.
    Object? error,
  }) = _AgentActionsState;
}

/// The buttons of the agent cards: login, logout, install and opening the settings.
///
/// One action at a time: a tap during another one is dropped. A login only starts here; it goes on
/// by itself, and its output arrives in [AgentActionsState.output]. The new status shows up in the
/// agents observed through `AgentsController`.
final class AgentActionsController extends StateController<AgentActionsState>
    with DroppableControllerHandler {
  AgentActionsController({
    required this._repository,
    super.initialState = const AgentActionsState(),
  });

  final IAgentsRepository _repository;
  final Map<String, (AgentLogin, VoidCallback)> _logins = <String, (AgentLogin, VoidCallback)>{};

  /// Signs [agentId] in with the method [methodId].
  void login(String agentId, String methodId) => _run(() async {
    final login = await _repository.login(agentId, methodId);
    if (!isDisposed) _follow(agentId, login);
  });

  /// Signs [agentId] out.
  void logout(String agentId) => _run(() async {
    await _repository.logout(agentId);
    if (isDisposed) return;
    _unfollow(agentId);
    _setOutput(agentId, null);
  });

  /// Installs [agentId].
  void install(String agentId) => _run(() => _repository.install(agentId));

  /// Opens the settings of [agentId].
  void openSettings(String agentId) => _run(() => _repository.openSettings(agentId));

  /// The widget has told the user about the last action's result.
  void acknowledge() {
    if (state.previewMilestone == null && state.error == null) return;
    setState(AgentActionsState(output: state.output));
  }

  void _run(Future<void> Function() action) => handle(() async {
    await action();
  }, error: (error, stackTrace) async {
    if (error is AgentPreviewException) {
      setState(AgentActionsState(output: state.output, previewMilestone: error.milestone));
    } else {
      setState(AgentActionsState(output: state.output, error: error));
    }
  });

  void _follow(String agentId, AgentLogin login) {
    _unfollow(agentId);
    void onOutput() {
      if (!isDisposed) _setOutput(agentId, login.output.value);
    }

    login.output.addListener(onOutput);
    _logins[agentId] = (login, onOutput);
    _setOutput(agentId, login.output.value);
  }

  void _unfollow(String agentId) {
    final (login, listener) = _logins.remove(agentId) ?? (null, null);
    if (login != null) login.output.removeListener(listener!);
  }

  void _setOutput(String agentId, List<String>? lines) {
    final output = <String, List<String>>{...state.output};
    if (lines == null) {
      output.remove(agentId);
    } else {
      output[agentId] = lines;
    }
    setState(state.copyWith(output: output));
  }

  @override
  void dispose() {
    for (final (login, listener) in _logins.values) {
      login.output.removeListener(listener);
    }
    _logins.clear();
    super.dispose();
  }
}
