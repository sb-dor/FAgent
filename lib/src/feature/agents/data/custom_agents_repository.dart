import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/agents/models/custom_agent_draft.dart';
import 'package:l/l.dart';

/// The ACP agents the user added.
abstract interface class ICustomAgentsRepository {
  /// The custom agents by creation time; again whenever one is added, changed or removed.
  /// Cancel the subscription to stop watching.
  ///
  /// A stored agent whose arguments or environment are not valid JSON is left out.
  Stream<List<AgentDefinition>> watch();

  /// Stores the agent of [draft] and returns its id, `custom:<n>`.
  Future<String> add(CustomAgentDraft draft);

  /// Replaces the fields of the custom agent [id] with those of [draft].
  Future<void> update(String id, CustomAgentDraft draft);

  /// Removes the custom agent [id].
  Future<void> remove(String id);
}

const String _idPrefix = 'custom:';

/// [ICustomAgentsRepository] over the `custom_agents` table.
final class CustomAgentsRepositoryImpl implements ICustomAgentsRepository {
  /// Creates the repository.
  CustomAgentsRepositoryImpl({required this._database});

  final AppDatabase _database;

  @override
  Stream<List<AgentDefinition>> watch() =>
      (_database.select(_database.customAgentsTable)..orderBy([
            (table) => OrderingTerm.asc(table.createdAt),
            (table) => OrderingTerm.asc(table.id),
          ]))
          .watch()
          .map(_definitions);

  @override
  Future<String> add(CustomAgentDraft draft) async {
    final id = await _database
        .into(_database.customAgentsTable)
        .insert(
          CustomAgentsTableCompanion.insert(
            name: draft.name,
            executable: draft.executable,
            arguments: Value(jsonEncode(draft.arguments)),
            environment: Value(jsonEncode(draft.environment)),
            rulesChannel: Value(draft.rulesChannel.name),
          ),
        );
    return '$_idPrefix$id';
  }

  @override
  Future<void> update(String id, CustomAgentDraft draft) async {
    final rowId = _rowId(id);
    if (rowId == null) throw ArgumentError.value(id, 'id', 'not a custom agent id');
    await (_database.update(
      _database.customAgentsTable,
    )..where((table) => table.id.equals(rowId))).write(
      CustomAgentsTableCompanion(
        name: Value(draft.name),
        executable: Value(draft.executable),
        arguments: Value(jsonEncode(draft.arguments)),
        environment: Value(jsonEncode(draft.environment)),
        rulesChannel: Value(draft.rulesChannel.name),
      ),
    );
  }

  @override
  Future<void> remove(String id) async {
    final rowId = _rowId(id);
    if (rowId == null) throw ArgumentError.value(id, 'id', 'not a custom agent id');
    await (_database.delete(
      _database.customAgentsTable,
    )..where((table) => table.id.equals(rowId))).go();
  }

  int? _rowId(String id) =>
      id.startsWith(_idPrefix) ? int.tryParse(id.substring(_idPrefix.length)) : null;

  List<AgentDefinition> _definitions(List<CustomAgentRow> rows) => [
    for (final row in rows) ?_definition(row),
  ];

  AgentDefinition? _definition(CustomAgentRow row) {
    try {
      final arguments = (jsonDecode(row.arguments) as List<Object?>).cast<String>();
      final environment = (jsonDecode(row.environment) as Map<String, Object?>)
          .cast<String, String>();
      return AgentDefinition(
        id: '$_idPrefix${row.id}',
        displayName: row.name,
        executable: row.executable,
        arguments: List<String>.unmodifiable(arguments),
        environment: Map<String, String>.unmodifiable(environment),
        rulesChannel:
            RulesChannel.values.asNameMap()[row.rulesChannel] ?? RulesChannel.firstMessage,
        source: AgentSource.custom,
      );
    } on Object catch (error) {
      l.w('CustomAgentsRepository | skipping $_idPrefix${row.id}: $error');
      return null;
    }
  }
}
