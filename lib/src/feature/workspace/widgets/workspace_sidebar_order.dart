import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_code_agent/src/feature/sessions/models/chat_session.dart';

/// Orders [projects] the way the sidebar shows its groups: the project with the most recent chat
/// first, ties in the order of [projects]; projects without chats follow in the order of
/// [projects].
List<Project> orderProjectsForSidebar(List<Project> projects, List<ChatSession> sessions) {
  final latest = <int, DateTime>{};
  for (final session in sessions) {
    final known = latest[session.projectId];
    if (known == null || session.updatedAt.isAfter(known))
      latest[session.projectId] = session.updatedAt;
  }
  final withChats = projects.where((p) => latest.containsKey(p.id)).toList()
    ..sort((a, b) {
      final byTime = latest[b.id]!.compareTo(latest[a.id]!);
      return byTime != 0 ? byTime : projects.indexOf(a).compareTo(projects.indexOf(b));
    });
  return <Project>[...withChats, ...projects.where((p) => !latest.containsKey(p.id))];
}
