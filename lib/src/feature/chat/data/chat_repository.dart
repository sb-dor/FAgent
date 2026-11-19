import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/session_event.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_runtime.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/slash_command.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';

/// A chat's runtime state and its recovery actions.
abstract interface class IChatRepository {
  /// Chat [sessionId] (its journal and live state): a first value once it is open, then a new
  /// one on every journal append and every change of its live state. A chat that cannot be
  /// opened is an error of the stream.
  Stream<ChatRuntime> watch(int sessionId);

  /// The status of chat [sessionId]: the current one once the chat is open, then every change.
  /// A chat that cannot be opened is an error of the stream.
  Stream<SessionStatus> watchStatus(int sessionId);

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
  Stream<ChatRuntime> watch(int sessionId) {
    // Synchronous: a listener sees every status the chat goes through, as with the notifiers.
    final controller = StreamController<ChatRuntime>(sync: true);
    LiveSession? session;
    StreamSubscription<SessionEvent>? added;
    var cancelled = false;
    // The agent's options and commands are mapped once per change, not once per value.
    List<Map<String, Object?>>? rawOptions;
    var options = const <ConfigOption>[];
    List<Map<String, Object?>>? rawCommands;
    var commands = const <SlashCommand>[];

    void emit() {
      final live = session;
      if (live == null || controller.isClosed) return;
      if (!identical(live.configOptions.value, rawOptions)) {
        rawOptions = live.configOptions.value;
        options = ConfigOption.parseAll(rawOptions!);
      }
      if (!identical(live.availableCommands.value, rawCommands)) {
        rawCommands = live.availableCommands.value;
        commands = agentCommands(rawCommands!);
      }
      controller.add(
        ChatRuntime(
          sessionId: live.id,
          agentId: live.agentId,
          events: live.store.eventsView,
          openPermissionIds: _hub.permissions.pendingFor(live.id).toSet(),
          status: live.status.value,
          problem: live.problem.value,
          canForceStop: live.canForceStop.value,
          canRetryPrompt: live.canRetryPrompt.value,
          configOptions: options,
          bypassBlocked: live.bypassBlocked,
          preparingTurn: live.preparingTurn.value,
          commands: commands,
        ),
      );
    }

    controller
      ..onListen = () async {
        final LiveSession live;
        try {
          live = await _hub.session(sessionId);
        } on Object catch (error, stackTrace) {
          if (!cancelled) {
            controller.addError(error, stackTrace);
            await controller.close();
          }
          return;
        }
        if (cancelled) return;
        session = live;
        added = live.store.added.listen((_) => emit());
        for (final notifier in _notifiers(live)) {
          notifier.addListener(emit);
        }
        emit();
      }
      ..onCancel = () async {
        cancelled = true;
        final live = session;
        session = null;
        // Allowed after the hub disposed the notifiers (the app closes).
        if (live != null) {
          for (final notifier in _notifiers(live)) {
            notifier.removeListener(emit);
          }
        }
        await added?.cancel();
        if (!controller.isClosed) await controller.close();
      };
    return controller.stream;
  }

  @override
  Stream<SessionStatus> watchStatus(int sessionId) {
    // Synchronous: a listener sees every status the chat goes through.
    final controller = StreamController<SessionStatus>(sync: true);
    ValueListenable<SessionStatus>? status;
    var cancelled = false;

    void emit() {
      if (status case final status? when !controller.isClosed) controller.add(status.value);
    }

    controller
      ..onListen = () async {
        final LiveSession live;
        try {
          live = await _hub.session(sessionId);
        } on Object catch (error, stackTrace) {
          if (!cancelled) {
            controller.addError(error, stackTrace);
            await controller.close();
          }
          return;
        }
        if (cancelled) return;
        status = live.status..addListener(emit);
        emit();
      }
      ..onCancel = () async {
        cancelled = true;
        // Allowed after the hub disposed the notifier (the app closes).
        status?.removeListener(emit);
        status = null;
        if (!controller.isClosed) await controller.close();
      };
    return controller.stream;
  }

  static List<Listenable> _notifiers(LiveSession session) => <Listenable>[
    session.status,
    session.problem,
    session.canForceStop,
    session.canRetryPrompt,
    session.configOptions,
    session.bypassAcknowledged,
    session.preparingTurn,
    session.availableCommands,
  ];

  @override
  Future<void> retry(int sessionId) => _hub.retry(sessionId);

  @override
  Future<void> startNewAgentSession(int sessionId) => _hub.startNewAgentSession(sessionId);
}
