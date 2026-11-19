import 'package:flutter_code_agent/src/common/acp/session_event.dart';
import 'package:flutter_code_agent/src/common/acp/session_problem.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/slash_command.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';
import 'package:meta/meta.dart';

/// {@template chat_runtime}
/// One chat at one moment: its journal and its live state, as the chat feature reads them.
/// {@endtemplate}
@immutable
final class ChatRuntime {
  /// {@macro chat_runtime}
  const ChatRuntime({
    required this.sessionId,
    required this.agentId,
    required this.events,
    required this.openPermissionIds,
    required this.status,
    required this.problem,
    required this.canForceStop,
    required this.canRetryPrompt,
    required this.configOptions,
    required this.bypassBlocked,
    required this.preparingTurn,
    required this.commands,
  });

  /// `sessions.id`.
  final int sessionId;

  /// Agent that runs the chat.
  final String agentId;

  /// The journal's visible events in `seq` order: a read-only view of the journal, not a copy, so
  /// it shows later events too; read it when the feed is folded.
  final List<SessionEvent> events;

  /// Permission request ids still open in this run.
  final Set<String> openPermissionIds;

  /// Session status.
  final SessionStatus status;

  /// Why the session cannot continue, if it cannot.
  final SessionProblem? problem;

  /// Stop hangs; the agent can be force-stopped.
  final bool canForceStop;

  /// The last prompt can be repeated after a login.
  final bool canRetryPrompt;

  /// Agent settings (mode, model, …), once the agent session exists.
  final List<ConfigOption> configOptions;

  /// The mode is `bypassPermissions` and the user has not allowed it for this chat.
  final bool bypassBlocked;

  /// The turn's prompt is not sent yet.
  final bool preparingTurn;

  /// Slash commands of the agent.
  final List<SlashCommand> commands;
}
