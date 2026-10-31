import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/tables/projects_table.dart';

/// The MCP servers the user added; the built-in ones live in code.
@DataClassName('McpServerRow')
class McpServersTable extends Table {
  @override
  String? get tableName => 'mcp_servers';

  IntColumn get id => integer().autoIncrement()();

  /// The name the agent sees; unique, checked case-insensitively by the repository.
  TextColumn get name => text().unique()();

  /// `stdio` or `http`.
  TextColumn get transport => text()();

  /// JSON: `{"command", "args", "env"}` for `stdio`, `{"url", "headers"}` for `http`.
  TextColumn get config => text()();

  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Where an MCP server is switched off. There is no row for a server that is on in a project.
@DataClassName('McpServerStateRow')
class McpServerStatesTable extends Table {
  @override
  String? get tableName => 'mcp_server_states';

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {serverKey, projectId},
  ];

  IntColumn get id => integer().autoIncrement()();

  /// `builtin:app`, `builtin:dart` or `user:<mcp_servers.id>`.
  TextColumn get serverKey => text()();

  IntColumn get projectId =>
      integer().references(ProjectsTable, #id, onDelete: KeyAction.cascade)();

  BoolColumn get enabled => boolean()();
}
