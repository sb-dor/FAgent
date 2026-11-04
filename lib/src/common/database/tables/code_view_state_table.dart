import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/tables/projects_table.dart';

/// What the Code view of a project shows: Chat or Code, the open files and the explorer's width.
/// There is no row for a project that never changed any of it.
@DataClassName('CodeViewStateRow')
class CodeViewStateTable extends Table {
  @override
  String? get tableName => 'code_view_state';

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{projectId};

  IntColumn get projectId =>
      integer().references(ProjectsTable, #id, onDelete: KeyAction.cascade)();

  /// `chat` or `code`.
  TextColumn get mode => text().withDefault(const Constant('chat'))();

  /// JSON list of the open files, relative to the project, in tab order.
  TextColumn get tabs => text().withDefault(const Constant('[]'))();

  /// The active tab, relative to the project; `null` for none.
  TextColumn get activeTab => text().nullable()();

  /// The explorer's width in logical pixels.
  RealColumn get explorerWidth => real().withDefault(const Constant(240))();
}
