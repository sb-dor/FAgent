import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/chat_queue/queued_chats.dart';
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

  /// Makes [agentId] run chat [sessionId], which has not started an agent session yet (its first
  /// message was not sent). The next time the chat opens it uses the new agent.
  ///
  /// Throws a [StateError] when the chat already has an agent session: its agent can no longer
  /// change.
  Future<void> setAgent(int sessionId, String agentId);

  /// Names chat [sessionId] [title] (trimmed); an empty name changes nothing. The automatic title
  /// fills only a chat without one, so the name stays.
  Future<void> rename(int sessionId, String title);

  /// Deletes chat [sessionId] with its history and its queued messages.
  ///
  /// Throws [ChatBusyException], and deletes nothing, while its agent works.
  Future<void> delete(int sessionId);
}

/// A chat was not deleted: its agent is working.
final class ChatBusyException implements Exception {
  /// Creates the exception for chat [sessionId].
  const ChatBusyException(this.sessionId);

  /// The chat that was kept.
  final int sessionId;

  @override
  String toString() => 'ChatBusyException: the agent works in chat $sessionId';
}

/// Drift and AgentHub backed [ISessionsRepository].
final class SessionsRepositoryImpl implements ISessionsRepository {
  /// Creates the repository.
  SessionsRepositoryImpl({required this._database, required this._hub, required this._queuedChats});

  final AppDatabase _database;
  final AgentHub _hub;
  final IQueuedChats _queuedChats;

  @override
  Future<void> rename(int sessionId, String title) async {
    final name = title.trim();
    if (name.isEmpty) return;
    await (_database.update(_database.sessionsTable)..where((s) => s.id.equals(sessionId))).write(
      SessionsTableCompanion(title: Value<String>(name)),
    );
  }

  // The foreign keys cascade (`PRAGMA foreign_keys = ON`): the chat's events go with it.
  @override
  Future<void> delete(int sessionId) async {
    if (_hub.opened(sessionId)?.status.value.isBusy ?? false) throw ChatBusyException(sessionId);
    await (_database.delete(_database.sessionsTable)..where((s) => s.id.equals(sessionId))).go();
    // A paused queue would otherwise stay forever and keep the quit question asking.
    _queuedChats.discard(sessionId);
  }

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

  @override
  Future<void> setAgent(int sessionId, String agentId) async {
    final sessions = _database.sessionsTable;
    final row = await (_database.select(
      sessions,
    )..where((s) => s.id.equals(sessionId))).getSingle();
    if (row.acpSessionId != null) {
      throw StateError('Chat $sessionId already has an agent session; its agent cannot change');
    }
    if (row.agentId == agentId) return;
    // The first message may already be on its way (the agent session is not stored yet while the
    // agent starts): the hub knows.
    if (!_hub.canChangeAgent(sessionId)) {
      throw StateError('Chat $sessionId is starting; its agent cannot change');
    }
    // Only while the chat still has no agent session, so the new agent never meets the old one's.
    final changed =
        await (_database.update(sessions)
              ..where((s) => s.id.equals(sessionId) & s.acpSessionId.isNull()))
            .write(SessionsTableCompanion(agentId: Value<String>(agentId)));
    if (changed == 0) {
      throw StateError('Chat $sessionId already has an agent session; its agent cannot change');
    }
    if (!await _hub.forget(sessionId)) {
      // A prompt got in between: put the agent back unless its session was stored meanwhile.
      await (_database.update(sessions)
            ..where((s) => s.id.equals(sessionId) & s.acpSessionId.isNull()))
          .write(SessionsTableCompanion(agentId: Value<String>(row.agentId)));
      throw StateError('Chat $sessionId is starting; its agent cannot change');
    }
  }
}
