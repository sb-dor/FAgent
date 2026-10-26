import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:meta/meta.dart';

/// {@template chat_view}
/// Everything the chat screen shows at one moment.
/// {@endtemplate}
@immutable
class ChatView {
  /// {@macro chat_view}
  const ChatView({
    required this.sessionId,
    required this.items,
    required this.status,
    this.problem,
    this.canForceStop = false,
    this.canRetryPrompt = false,
  });

  /// `sessions.id`.
  final int sessionId;

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
}
