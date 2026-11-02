import 'dart:async';

import 'package:control/control.dart';
import 'package:dart_acp_sdk/dart_acp_sdk.dart' show CancellationException;
import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/acp/agent_auth.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agents_repository.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/agents/models/custom_agent_draft.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'agent_actions_controller.freezed.dart';

/// What the buttons of the agent cards have done so far.
@freezed
abstract class AgentActionsState with _$AgentActionsState {
  const factory AgentActionsState({
    /// The output lines of the latest terminal login of each agent (agent id → lines).
    @Default(<String, List<String>>{}) Map<String, List<String>> output,

    /// Agents with an ACP sign-in (browser or API key) in flight.
    @Default(<String>{}) Set<String> signingIn,

    /// The last action failed with this; never a cancelled sign-in.
    Object? error,
  }) = _AgentActionsState;
}

/// The buttons of the agent cards: sign-in and sign-out, the settings, and the custom agents.
///
/// One action at a time: a tap during another one is dropped. A sign-in only starts here and goes on
/// by itself: a terminal login's output arrives in [AgentActionsState.output], a browser or key
/// sign-in is in [AgentActionsState.signingIn] until it ends, without holding other actions back.
/// The new status shows up in the agents observed through `AgentsController`.
final class AgentActionsController extends StateController<AgentActionsState>
    with DroppableControllerHandler {
  AgentActionsController({
    required this._repository,
    super.initialState = const AgentActionsState(),
  });

  final IAgentsRepository _repository;
  final Map<String, (AgentLogin, VoidCallback)> _logins = <String, (AgentLogin, VoidCallback)>{};

  /// Signs [agentId] in with [method].
  ///
  /// A browser or key sign-in is in [AgentActionsState.signingIn] as soon as this returns; a second
  /// one of the same agent while it runs is dropped.
  void login(String agentId, AgentLoginMethod method) {
    if (method.kind == AgentLoginKind.terminal) {
      _run(() async {
        final login = await _repository.login(agentId, method.id);
        if (!isDisposed && login != null) _follow(agentId, login);
      });
      return;
    }
    if (isDisposed || state.signingIn.contains(agentId)) return;
    _setSigningIn(agentId, signingIn: true);
    // The user may take minutes in the browser, so this holds no other action back.
    unawaited(
      _repository
          .login(agentId, method.id)
          .then<void>(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              if (isDisposed || error is CancellationException) return;
              setState(state.copyWith(error: error));
            },
          )
          .whenComplete(() {
            if (!isDisposed) _setSigningIn(agentId, signingIn: false);
          }),
    );
  }

  /// Stops the running browser or key sign-in of [agentId].
  void cancelLogin(String agentId) => _run(() => _repository.cancelLogin(agentId));

  /// Signs [agentId] out.
  void logout(String agentId) => _run(() async {
    await _repository.logout(agentId);
    if (isDisposed) return;
    _unfollow(agentId);
    _setOutput(agentId, null);
  });

  /// Whether a chat of [agentId] is working, so signing it out or removing it would stop the chat.
  Future<bool> hasBusyChats(String agentId) => _repository.hasBusyChats(agentId);

  /// Opens the settings of [agentId].
  void openSettings(String agentId) => _run(() => _repository.openSettings(agentId));

  /// Adds the custom agent of [draft].
  void addCustom(CustomAgentDraft draft) => _run(() => _repository.addCustom(draft));

  /// Replaces the custom agent [id] with [draft].
  void updateCustom(String id, CustomAgentDraft draft) =>
      _run(() => _repository.updateCustom(id, draft));

  /// Removes the custom agent [id].
  void removeCustom(String id) => _run(() => _repository.removeCustom(id));

  /// The widget has told the user about the last action's result.
  void acknowledge() {
    if (state.error == null) return;
    setState(state.copyWith(error: null));
  }

  void _run(Future<void> Function() action) => handle(() async {
    await action();
  }, error: (error, stackTrace) async => setState(state.copyWith(error: error)));

  void _setSigningIn(String agentId, {required bool signingIn}) => setState(
    state.copyWith(
      signingIn: signingIn
          ? <String>{...state.signingIn, agentId}
          : <String>{...state.signingIn}.difference(<String>{agentId}),
    ),
  );

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
