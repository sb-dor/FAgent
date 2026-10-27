import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/acp/session_event_store.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';

/// Operation that was interrupted and can be repeated.
enum SessionOperation {
  /// Starting the agent process.
  start,

  /// `session/load`.
  load,

  /// `session/new`.
  create,

  /// `session/prompt`.
  prompt,
}

/// Why a session is not usable right now.
enum SessionProblemKind {
  /// The machine cannot run the agent (Node.js or the executable is missing).
  preflight,

  /// The agent process did not start or initialize.
  start,

  /// `session/load` says the agent session does not exist (-32002).
  notFound,

  /// A request failed or timed out; retrying may help.
  transient,

  /// The agent needs a login.
  auth,

  /// The agent process stopped.
  crash,

  /// The turn does not end after Stop.
  stuck,
}

/// {@template session_problem}
/// What the UI shows for `setupFailed`, `needsAuth`, `error` and a stuck stop.
/// {@endtemplate}
@immutable
final class SessionProblem {
  /// {@macro session_problem}
  const SessionProblem(this.kind, this.message, {this.hint, this.details = const <String>[]});

  /// Category, decides which actions the UI offers.
  final SessionProblemKind kind;

  /// Human-readable cause.
  final String message;

  /// How to fix it, when known.
  final String? hint;

  /// Diagnostic lines (agent stderr tail).
  final List<String> details;

  @override
  String toString() => 'SessionProblem(${kind.name}: $message)';
}

/// {@template live_session}
/// Runtime state of one chat: its journal, status and the agent session.
///
/// Created and owned by `AgentHub`; the UI only listens.
/// {@endtemplate}
final class LiveSession {
  /// {@macro live_session}
  LiveSession({
    required this.id,
    required this.agentId,
    required this.cwd,
    required this.store,
    this.acpSessionId,
  });

  /// `sessions.id`.
  final int id;

  /// Agent that runs the chat.
  final String agentId;

  /// Project folder (`session/new` cwd).
  final String cwd;

  /// The chat journal.
  final SessionEventStore store;

  /// ACP session id, once the agent session exists.
  String? acpSessionId;

  /// Current status.
  final ValueNotifier<SessionStatus> status = ValueNotifier<SessionStatus>(SessionStatus.cold);

  /// Why the session is in `setupFailed`, `needsAuth` or `error`, or why Stop hangs.
  final ValueNotifier<SessionProblem?> problem = ValueNotifier<SessionProblem?>(null);

  /// Stop did not end the turn in time; the agent process can be killed.
  final ValueNotifier<bool> canForceStop = ValueNotifier<bool>(false);

  /// The last prompt failed before running (login needed); it can be repeated.
  final ValueNotifier<bool> canRetryPrompt = ValueNotifier<bool>(false);

  /// Raw `configOptions` (mode, model, …) as last reported by the agent.
  final ValueNotifier<List<Map<String, Object?>>> configOptions =
      ValueNotifier<List<Map<String, Object?>>>(const <Map<String, Object?>>[]);

  /// The user allowed `bypassPermissions` for this chat (stored with the
  /// chat). Until then a chat whose mode is bypass does not accept prompts.
  final ValueNotifier<bool> bypassAcknowledged = ValueNotifier<bool>(false);

  /// The turn is reserved but its prompt is not sent yet (snapshots of the
  /// project are being taken).
  final ValueNotifier<bool> preparingTurn = ValueNotifier<bool>(false);

  /// The agent's permission mode is `bypassPermissions` (e.g. from the user's
  /// Claude settings or a loaded session) and the user has not allowed it in
  /// this run.
  bool get bypassBlocked =>
      !bypassAcknowledged.value &&
      configOptions.value.any((o) => isModeOption(o) && o['currentValue'] == bypassMode);

  /// Permission mode that accepts every permission.
  static const String bypassMode = 'bypassPermissions';

  /// Whether raw config option [option] is the permission mode.
  static bool isModeOption(Map<String, Object?> option) =>
      option['id'] == 'mode' || option['category'] == 'mode';

  /// Raw `availableCommands` (slash commands). Kept in memory only.
  final ValueNotifier<List<Map<String, Object?>>> availableCommands =
      ValueNotifier<List<Map<String, Object?>>>(const <Map<String, Object?>>[]);

  /// Operation to repeat after `setupFailed` or a login.
  SessionOperation? interrupted;

  /// Content of the last prompt, for "repeat after login".
  List<Map<String, Object?>>? lastPrompt;

  /// While `session/load` replays history, frames are not journaled.
  bool replaying = false;

  /// End of the running turn, if any.
  Future<void>? turn;

  /// Offers force-stop when Stop takes too long; cancelled when the turn ends.
  Timer? cancelTimer;

  /// Releases the notifiers. Called by `AgentHub.dispose` after `disposed`.
  void dispose() {
    cancelTimer?.cancel();
    status.dispose();
    problem.dispose();
    canForceStop.dispose();
    canRetryPrompt.dispose();
    configOptions.dispose();
    bypassAcknowledged.dispose();
    preparingTurn.dispose();
    availableCommands.dispose();
  }

  @override
  String toString() => 'LiveSession($id, ${status.value.name})';
}
