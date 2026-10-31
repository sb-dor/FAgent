import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/models/skill_library.dart';

/// Builds the library for the project [projectId] from [items] and the `skill_states` [states].
///
/// An item without a row is on. A row without a project is the global value, a row with one is the
/// project's own; [KnowledgeItem.exceptions] lists the projects whose value differs from the global.
SkillLibrary applySkillStates(
  List<KnowledgeItem> items,
  List<SkillStateRow> states,
  int? projectId,
) {
  final globalById = {
    for (final row in states)
      if (row.projectId == null) row.skillId: row.enabled,
  };
  final projectRows = <String, Map<int, bool>>{};
  for (final row in states) {
    if (row.projectId case final project?) {
      (projectRows[row.skillId] ??= {})[project] = row.enabled;
    }
  }

  KnowledgeItem apply(KnowledgeItem item) {
    final global = globalById[item.id] ?? true;
    final rows = projectRows[item.id] ?? const <int, bool>{};
    return item.copyWith(
      enabledGlobally: global,
      enabled: projectId == null ? global : rows[projectId] ?? global,
      exceptions: {
        for (final MapEntry(:key, :value) in rows.entries)
          if (value != global) key,
      },
    );
  }

  final applied = items.map(apply).toList();
  return SkillLibrary(
    skills: applied.where((item) => item.kind == KnowledgeKind.skill).toList(),
    rules: applied.where((item) => item.kind == KnowledgeKind.rule).toList(),
  );
}

/// Turns the item [id] on or off globally ([projectId] is `null`) or for one project.
///
/// A global change replaces the global row and drops the project rows that now equal it; a project
/// change that equals the global value removes the project's row instead of storing it. The global
/// row is found with `IS NULL` because SQLite treats `NULL`s in the unique key as different.
Future<void> setSkillEnabled(
  AppDatabase database,
  String id, {
  required bool enabled,
  int? projectId,
}) {
  final table = database.skillStatesTable;
  Selectable<SkillStateRow> rowsOf(Expression<bool> Function($SkillStatesTableTable) project) =>
      database.select(table)..where((row) => row.skillId.equals(id) & project(row));

  return database.transaction(() async {
    if (projectId == null) {
      await (database.delete(
        table,
      )..where((row) => row.skillId.equals(id) & row.projectId.isNull())).go();
      await database
          .into(table)
          .insert(SkillStatesTableCompanion.insert(skillId: id, enabled: enabled));
      await (database.delete(table)..where(
            (row) =>
                row.skillId.equals(id) & row.projectId.isNotNull() & row.enabled.equals(enabled),
          ))
          .go();
      return;
    }

    final global = await rowsOf((row) => row.projectId.isNull()).getSingleOrNull();
    final existing = await rowsOf((row) => row.projectId.equals(projectId)).getSingleOrNull();
    if (enabled == (global?.enabled ?? true)) {
      if (existing != null) await database.delete(table).delete(existing);
    } else if (existing != null) {
      await database.update(table).replace(existing.copyWith(enabled: enabled));
    } else {
      await database
          .into(table)
          .insert(
            SkillStatesTableCompanion.insert(
              skillId: id,
              projectId: Value(projectId),
              enabled: enabled,
            ),
          );
    }
  });
}

/// Removes the project's own value for [id], so the project follows the global one.
Future<void> clearSkillException(AppDatabase database, String id, int projectId) =>
    (database.delete(
      database.skillStatesTable,
    )..where((row) => row.skillId.equals(id) & row.projectId.equals(projectId))).go();
