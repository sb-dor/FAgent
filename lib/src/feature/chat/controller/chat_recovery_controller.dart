import 'dart:async';

import 'package:control/control.dart';
import 'package:dart_acp_sdk/dart_acp_sdk.dart' show CancellationException;
import 'package:flutter_code_agent/src/common/acp/agent_auth.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agents_repository.dart';
import 'package:flutter_code_agent/src/feature/chat/data/chat_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:l/l.dart';

part 'chat_recovery_controller.freezed.dart';

@freezed
sealed class ChatRecoveryState with _$ChatRecoveryState {
  const factory ChatRecoveryState.initial() = ChatRecovery$InitialState;

  /// [output]: lines of a running login; [cancellable]: a browser or key sign-in that Cancel
  /// stops.
  const factory ChatRecoveryState.inProgress({
    @Default(<String>[]) List<String> output,
    @Default(false) bool cancellable,
  }) = ChatRecovery$InProgressState;

  /// [output]: lines of the failed login, for the user to read.
  const factory ChatRecoveryState.error({Object? error, @Default(<String>[]) List<String> output}) =
      ChatRecovery$ErrorState;

  const factory ChatRecoveryState.completed() = ChatRecovery$CompletedState;
}

/// Recovery actions offered by the problem banner. The chat's status shows
/// the outcome; this controller only guards against double clicks.
final class ChatRecoveryController extends StateController<ChatRecoveryState>
    with DroppableControllerHandler {
  ChatRecoveryController({
    required this._chat,
    required this._agents,
    super.initialState = const ChatRecoveryState.initial(),
  });

  final IChatRepository _chat;
  final IAgentsRepository _agents;

  void retry(int sessionId) => handle(() async {
    setState(const ChatRecoveryState.inProgress());
    await _chat.retry(sessionId);
    setState(const ChatRecoveryState.completed());
  }, error: (error, stackTrace) async => setState(ChatRecoveryState.error(error: error)));

  /// Signs [agentId] in with [methodId]; [cancellable] for a browser or key sign-in, which
  /// [cancelLogin] stops.
  void login(String agentId, String methodId, {bool cancellable = false}) {
    var output = const <String>[];
    handle(
      () async {
        setState(ChatRecoveryState.inProgress(cancellable: cancellable));
        final succeeded = await _signIn(
          agentId,
          methodId,
          onOutput: (lines) {
            output = lines;
            if (!isDisposed) {
              setState(ChatRecoveryState.inProgress(output: lines, cancellable: cancellable));
            }
          },
        );
        setState(
          succeeded ? const ChatRecoveryState.completed() : ChatRecoveryState.error(output: output),
        );
      },
      error: (error, stackTrace) async =>
          setState(ChatRecoveryState.error(error: error, output: output)),
    );
  }

  /// `true` when [agentId] signed in with [methodId], `false` when it failed or was cancelled.
  /// [onOutput] gets a terminal login's output lines as they come.
  Future<bool> _signIn(
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
    return terminal.succeeded.whenComplete(() => terminal.output.removeListener(listener));
  }

  /// Stops the running browser or key sign-in of [agentId]; the login then ends as failed.
  ///
  /// Runs outside [handle]: the sign-in it stops holds the handler.
  void cancelLogin(String agentId) {
    if (isDisposed) return;
    unawaited(
      _agents.cancelLogin(agentId).catchError((Object error, StackTrace stackTrace) {
        l.w('Chat | cancelling the sign-in of $agentId failed: $error', stackTrace);
      }),
    );
  }

  void startNewAgentSession(int sessionId) => handle(() async {
    setState(const ChatRecoveryState.inProgress());
    await _chat.startNewAgentSession(sessionId);
    setState(const ChatRecoveryState.completed());
  }, error: (error, stackTrace) async => setState(ChatRecoveryState.error(error: error)));
}
