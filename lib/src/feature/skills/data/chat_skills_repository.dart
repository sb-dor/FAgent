import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';

/// Which skills a single chat turns on or off against its project.
abstract interface class IChatSkillsRepository {
  /// The chat's choices by skill id: the current ones at once, then again whenever they change.
  /// Only skills that differ from the project are in the map. Cancel the subscription to stop
  /// watching.
  Stream<Map<String, bool>> watch(int sessionId);

  /// The chat's choices by skill id right now.
  Future<Map<String, bool>> current(int sessionId);

  /// Turns [skillId] on or off for the chat. [projectEnabled] is the skill's state in the chat's
  /// project: a choice equal to it is not stored, and removes the earlier one.
  Future<void> set(
    int sessionId,
    String skillId, {
    required bool enabled,
    required bool projectEnabled,
  });
}

/// {@template chat_skills_repository}
/// [IChatSkillsRepository] on the `chat_skill_states` table.
/// {@endtemplate}
final class ChatSkillsRepositoryImpl implements IChatSkillsRepository {
  /// {@macro chat_skills_repository}
  const ChatSkillsRepositoryImpl({required this._database});

  final AppDatabase _database;

  SimpleSelectStatement<$ChatSkillStatesTableTable, ChatSkillStateRow> _rowsOf(int sessionId) =>
      _database.select(_database.chatSkillStatesTable)..where((t) => t.sessionId.equals(sessionId));

  Map<String, bool> _byId(List<ChatSkillStateRow> rows) => {
    for (final row in rows) row.skillId: row.enabled,
  };

  @override
  Stream<Map<String, bool>> watch(int sessionId) {
    final controller = StreamController<Map<String, bool>>();
    StreamSubscription<List<ChatSkillStateRow>>? subscription;
    Map<String, bool>? emitted;
    controller
      ..onListen = () {
        subscription = _rowsOf(sessionId).watch().listen(
          (rows) {
            final states = _byId(rows);
            if (controller.isClosed || mapEquals(states, emitted)) return;
            controller.add(emitted = states);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!controller.isClosed) controller.addError(error, stackTrace);
          },
        );
      }
      ..onCancel = () async {
        await subscription?.cancel();
        if (!controller.isClosed) await controller.close();
      };
    return controller.stream;
  }

  @override
  Future<Map<String, bool>> current(int sessionId) async => _byId(await _rowsOf(sessionId).get());

  @override
  Future<void> set(
    int sessionId,
    String skillId, {
    required bool enabled,
    required bool projectEnabled,
  }) {
    final table = _database.chatSkillStatesTable;
    if (enabled == projectEnabled) {
      return (_database.delete(
        table,
      )..where((t) => t.sessionId.equals(sessionId) & t.skillId.equals(skillId))).go();
    }
    return _database
        .into(table)
        .insertOnConflictUpdate(
          ChatSkillStatesTableCompanion.insert(
            sessionId: sessionId,
            skillId: skillId,
            enabled: enabled,
          ),
        );
  }
}
