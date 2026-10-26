import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/tables/projects_table.dart';

/// Chats with an agent inside a project.
@DataClassName('SessionRow')
class SessionsTable extends Table {
  @override
  String? get tableName => 'sessions';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get projectId =>
      integer().references(ProjectsTable, #id, onDelete: KeyAction.cascade)();

  /// `AgentDefinition.id` of the agent that runs this chat.
  TextColumn get agentId => text()();

  /// ACP session id; `null` until the first prompt creates the agent session.
  TextColumn get acpSessionId => text().nullable()();

  /// First 60 characters of the first prompt.
  TextColumn get title => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
