import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';
import 'package:meta/meta.dart';

/// {@template chat_view}
/// Everything the chat screen shows at one moment.
/// {@endtemplate}
@immutable
class ChatView {
  /// {@macro chat_view}
  const ChatView({
    required this.sessionId,
    required this.agentId,
    required this.items,
    required this.status,
    this.problem,
    this.canForceStop = false,
    this.canRetryPrompt = false,
    this.configOptions = const <ConfigOption>[],
    this.bypassBlocked = false,
    this.preparingTurn = false,
  });

  /// `sessions.id`.
  final int sessionId;

  /// Agent that runs the chat.
  final String agentId;

  /// The feed.
  final List<ChatItem> items;

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

  /// The mode is `bypassPermissions` and the user has not allowed it for this
  /// chat: prompts are blocked.
  final bool bypassBlocked;

  /// The turn's prompt is not sent yet.
  final bool preparingTurn;

  /// Agent settings can be changed in this status.
  bool get canChangeConfig => switch (status) {
    SessionStatus.idle || SessionStatus.running || SessionStatus.awaitingPermission => true,
    _ => false,
  };

  /// The chat already has a message of the user, so its agent can no longer be changed.
  bool get agentLocked => items.any((item) => item is UserMessageItem);
}
