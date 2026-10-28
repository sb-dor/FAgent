import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/sessions/models/chat_session.dart';

/// Chats of every project.
abstract interface class ISessionsRepository {
  /// Chats of all projects, most recently active first. Closes when cancelled.
  Stream<List<ChatSession>> watchAllSessions();

  /// Chats of [projectId], most recently active first. Closes when cancelled.
  Stream<List<ChatSession>> watchSessions(int projectId);

  /// Live status of chat [sessionId], or `null` while it was not opened in
  /// this run (it is then `cold`).
  ValueListenable<SessionStatus>? statusOf(int sessionId);
}

/// Drift and AgentHub backed [ISessionsRepository].
final class SessionsRepositoryImpl implements ISessionsRepository {
  /// Creates the repository.
  SessionsRepositoryImpl({required this._database, required this._hub});

  final AppDatabase _database;
  final AgentHub _hub;

  @override
  Stream<List<ChatSession>> watchAllSessions() =>
      (_database.select(_database.sessionsTable)..orderBy(
            <OrderClauseGenerator<$SessionsTableTable>>[(s) => OrderingTerm.desc(s.updatedAt)],
          ))
          .watch()
          .map((rows) => rows.map(ChatSession.fromRow).toList(growable: false));

  @override
  Stream<List<ChatSession>> watchSessions(int projectId) =>
      (_database.select(_database.sessionsTable)
            ..where((s) => s.projectId.equals(projectId))
            ..orderBy(<OrderClauseGenerator<$SessionsTableTable>>[
              (s) => OrderingTerm.desc(s.updatedAt),
            ]))
          .watch()
          .map((rows) => rows.map(ChatSession.fromRow).toList(growable: false));

  @override
  ValueListenable<SessionStatus>? statusOf(int sessionId) => _hub.opened(sessionId)?.status;
}
