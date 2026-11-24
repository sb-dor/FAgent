import 'package:meta/meta.dart';

/// {@template chat_search_result}
/// A chat found by the chat search.
/// {@endtemplate}
@immutable
final class ChatSearchResult {
  /// {@macro chat_search_result}
  const ChatSearchResult({
    required this.sessionId,
    required this.projectId,
    required this.title,
    required this.projectName,
    required this.updatedAt,
  });

  /// `sessions.id`.
  final int sessionId;

  /// `projects.id` of the project the chat belongs to.
  final int projectId;

  /// Title of the chat; empty while the chat has none.
  final String title;

  /// Name of the project the chat belongs to.
  final String projectName;

  /// When the chat last changed.
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatSearchResult &&
          other.sessionId == sessionId &&
          other.projectId == projectId &&
          other.title == title &&
          other.projectName == projectName &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(sessionId, projectId, title, projectName, updatedAt);
}
