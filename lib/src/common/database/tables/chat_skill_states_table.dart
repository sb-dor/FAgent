import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/tables/sessions_table.dart';

/// Whether a skill is on in one chat when that differs from the chat's project. There is no row for
/// a skill that follows its project; deleting the chat deletes its rows.
@DataClassName('ChatSkillStateRow')
class ChatSkillStatesTable extends Table {
  @override
  String? get tableName => 'chat_skill_states';

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{sessionId, skillId};

  IntColumn get sessionId =>
      integer().references(SessionsTable, #id, onDelete: KeyAction.cascade)();

  /// `KnowledgeItem.id`, for example `skill:builtin:feature-architecture`.
  TextColumn get skillId => text()();

  BoolColumn get enabled => boolean()();
}
