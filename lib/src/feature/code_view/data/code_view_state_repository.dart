import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/code_view_state.dart';

/// The remembered Code view of each project.
abstract interface class ICodeViewStateRepository {
  /// The state of [projectId]; the default when it was never saved.
  Future<CodeViewState> load(int projectId);

  /// Remembers [state] for [projectId].
  Future<void> save(int projectId, CodeViewState state);
}

/// drift-backed [ICodeViewStateRepository].
final class CodeViewStateRepositoryImpl implements ICodeViewStateRepository {
  /// Creates the repository.
  CodeViewStateRepositoryImpl({required this._database});

  final AppDatabase _database;

  @override
  Future<CodeViewState> load(int projectId) async {
    final row = await (_database.select(
      _database.codeViewStateTable,
    )..where((row) => row.projectId.equals(projectId))).getSingleOrNull();
    if (row == null) return const CodeViewState();
    return CodeViewState(
      mode: CodeViewMode.values.asNameMap()[row.mode] ?? CodeViewMode.chat,
      tabs: _decodeTabs(row.tabs),
      activeTab: row.activeTab,
      explorerWidth: row.explorerWidth,
    );
  }

  static List<String> _decodeTabs(String json) {
    try {
      final decoded = jsonDecode(json);
      return decoded is List ? <String>[...decoded.whereType<String>()] : const <String>[];
    } on FormatException {
      return const <String>[];
    }
  }

  @override
  Future<void> save(int projectId, CodeViewState state) => _database
      .into(_database.codeViewStateTable)
      .insertOnConflictUpdate(
        CodeViewStateTableCompanion.insert(
          projectId: Value(projectId),
          mode: Value(state.mode.name),
          tabs: Value(jsonEncode(state.tabs)),
          activeTab: Value(state.activeTab),
          explorerWidth: Value(state.explorerWidth),
        ),
      );
}
