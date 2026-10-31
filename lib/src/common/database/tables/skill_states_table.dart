import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/tables/projects_table.dart';

/// Whether a skill or rule is on. There is no row for an item that is on everywhere.
///
/// A row with a `null` [projectId] is the global value; a row with a project is an exception to it.
/// SQLite treats `NULL`s in a unique key as different, so the global row is looked up and replaced
/// explicitly by the repository.
@DataClassName('SkillStateRow')
class SkillStatesTable extends Table {
  @override
  String? get tableName => 'skill_states';

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {skillId, projectId},
  ];

  IntColumn get id => integer().autoIncrement()();

  /// `KnowledgeItem.id`, for example `skill:builtin:feature-architecture`.
  TextColumn get skillId => text()();

  /// The project the row is an exception for; `null` for the global row.
  IntColumn get projectId =>
      integer().nullable().references(ProjectsTable, #id, onDelete: KeyAction.cascade)();

  BoolColumn get enabled => boolean()();
}
