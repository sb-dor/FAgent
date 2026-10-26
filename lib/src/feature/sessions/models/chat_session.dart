import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:meta/meta.dart';

/// {@template chat_session}
/// A chat in the sidebar.
/// {@endtemplate}
@immutable
class ChatSession {
  /// {@macro chat_session}
  const ChatSession({
    required this.id,
    required this.projectId,
    required this.agentId,
    required this.title,
    required this.updatedAt,
  });

  /// Maps a database row.
  factory ChatSession.fromRow(SessionRow row) => ChatSession(
    id: row.id,
    projectId: row.projectId,
    agentId: row.agentId,
    title: row.title,
    updatedAt: row.updatedAt,
  );

  /// `sessions.id`.
  final int id;

  /// Project the chat belongs to.
  final int projectId;

  /// Agent that runs the chat.
  final String agentId;

  /// First words of the first prompt; empty for a new chat.
  final String title;

  /// Last activity.
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      other is ChatSession &&
      other.id == id &&
      other.projectId == projectId &&
      other.agentId == agentId &&
      other.title == title &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, projectId, agentId, title, updatedAt);
}
