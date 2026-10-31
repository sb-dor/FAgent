import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_json.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_exceptions.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_server.dart';

/// The MCP servers handed to agents: the app's built-in ones and the user's own.
abstract interface class IMcpServersRepository {
  /// The built-in servers, then the user's by creation time; again whenever any of them or the
  /// per-project switches change. Cancel the subscription to stop watching.
  Stream<List<McpServer>> watchServers();

  /// Adds the server of [draft] and returns it.
  ///
  /// Throws [InvalidMcpServerException] when the name is not `^[A-Za-z0-9_.-]{1,64}$`, is reserved
  /// or is taken (case-insensitively), when a `stdio` server has no command or when an `http`
  /// server has no `http`/`https` URL with a host.
  Future<McpServer> add(McpServerDraft draft);

  /// Removes the user's server [id] and its per-project switches; a built-in one is an
  /// [ArgumentError].
  Future<void> remove(String id);

  /// Turns [id] on or off.
  ///
  /// Without [projectId] it changes the server everywhere, which only the user's servers allow (a
  /// built-in one is an [ArgumentError]). With a project, `false` switches the server off there
  /// and `true` removes that switch.
  Future<void> setEnabled(String id, {required bool enabled, int? projectId});

  /// Adds the servers of the `.mcp.json` at [path] and reports the ones it left out.
  ///
  /// A taken name is skipped (`name is taken`), as is an entry [add] refuses (with the problem's
  /// name) or [parseMcpJson] cannot use; existing servers are never changed. Throws
  /// [McpJsonException] when the file is not a `.mcp.json`.
  Future<({List<String> added, List<(String name, String reason)> skipped})> importMcpJson(
    String path,
  );
}

const String _appKey = 'builtin:app';
const String _dartKey = 'builtin:dart';

final RegExp _validName = RegExp(r'^[A-Za-z0-9_.-]{1,64}$');

/// Names the built-in servers go by, so a user's server must not use them.
const Set<String> _reservedNames = {'flutter_code_agent', 'dart mcp', 'dart'};

McpServer _builtinApp(Set<int> disabledIn) => McpServer(
  id: _appKey,
  name: 'flutter_code_agent',
  transport: McpTransport.stdio,
  builtin: true,
  disabledIn: disabledIn,
  status: McpStatus.ready,
  toolCount: 9,
  summary: 'skills, rules, run, screenshot',
);

McpServer _builtinDart(Set<int> disabledIn) => McpServer(
  id: _dartKey,
  name: 'Dart MCP',
  transport: McpTransport.stdio,
  command: 'dart',
  args: const ['mcp-server'],
  builtin: true,
  disabledIn: disabledIn,
  status: McpStatus.ready,
  toolCount: 18,
  summary: 'hot reload, analysis, pub.dev',
);

/// [IMcpServersRepository] over the `mcp_servers` and `mcp_server_states` tables.
final class McpServersRepositoryImpl implements IMcpServersRepository {
  /// Creates the repository.
  McpServersRepositoryImpl({required this._database});

  final AppDatabase _database;

  @override
  Stream<List<McpServer>> watchServers() {
    final controller = StreamController<List<McpServer>>();
    StreamSubscription<List<McpServerRow>>? rowsSubscription;
    StreamSubscription<List<McpServerStateRow>>? statesSubscription;
    List<McpServerRow>? rows;
    List<McpServerStateRow>? states;
    List<McpServer>? emitted;

    void emit() {
      final currentRows = rows;
      final currentStates = states;
      if (controller.isClosed || currentRows == null || currentStates == null) return;
      final servers = _combine(currentRows, currentStates);
      if (listEquals(servers, emitted)) return;
      controller.add(emitted = servers);
    }

    void fail(Object error, StackTrace stackTrace) {
      if (!controller.isClosed) controller.addError(error, stackTrace);
    }

    controller
      ..onListen = () {
        rowsSubscription =
            (_database.select(_database.mcpServersTable)
                  ..orderBy([(t) => OrderingTerm.asc(t.createdAt), (t) => OrderingTerm.asc(t.id)]))
                .watch()
                .listen((value) {
                  rows = value;
                  emit();
                }, onError: fail);
        statesSubscription = _database.select(_database.mcpServerStatesTable).watch().listen((
          value,
        ) {
          states = value;
          emit();
        }, onError: fail);
      }
      ..onCancel = () async {
        await rowsSubscription?.cancel();
        await statesSubscription?.cancel();
        await controller.close();
      };
    return controller.stream;
  }

  List<McpServer> _combine(List<McpServerRow> rows, List<McpServerStateRow> states) {
    final disabled = <String, Set<int>>{};
    for (final state in states) {
      if (!state.enabled) (disabled[state.serverKey] ??= {}).add(state.projectId);
    }
    return [
      _builtinApp(disabled[_appKey] ?? const {}),
      _builtinDart(disabled[_dartKey] ?? const {}),
      for (final row in rows) _fromRow(row, disabled['user:${row.id}'] ?? const {}),
    ];
  }

  McpServer _fromRow(McpServerRow row, Set<int> disabledIn) {
    final transport = McpTransport.values.asNameMap()[row.transport] ?? McpTransport.stdio;
    final config = _decodeConfig(row.config);
    return McpServer(
      id: 'user:${row.id}',
      name: row.name,
      transport: transport,
      command: config['command'] as String?,
      args: _stringList(config['args']),
      env: _stringMap(config['env']),
      url: config['url'] as String?,
      headers: _stringMap(config['headers']),
      enabled: row.enabled,
      disabledIn: disabledIn,
    );
  }

  Map<String, Object?> _decodeConfig(String text) {
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, Object?> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

  List<String> _stringList(Object? value) => [
    if (value is List<Object?>)
      for (final item in value)
        if (item is String) item,
  ];

  Map<String, String> _stringMap(Object? value) => {
    if (value is Map<String, Object?>)
      for (final MapEntry(:key, :value) in value.entries)
        if (value is String) key: value,
  };

  // --- Adding and removing ---

  @override
  Future<McpServer> add(McpServerDraft draft) {
    final name = draft.name;
    if (!_validName.hasMatch(name) || _reservedNames.contains(name.toLowerCase())) {
      throw const InvalidMcpServerException(McpServerProblem.invalidName);
    }
    final config = <String, Object?>{};
    switch (draft.transport) {
      case McpTransport.stdio:
        final command = draft.command?.trim() ?? '';
        if (command.isEmpty) {
          throw const InvalidMcpServerException(McpServerProblem.missingCommand);
        }
        config
          ..['command'] = command
          ..['args'] = draft.args
          ..['env'] = draft.env;
      case McpTransport.http:
        final uri = Uri.tryParse(draft.url?.trim() ?? '');
        if (uri == null || !{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
          throw const InvalidMcpServerException(McpServerProblem.invalidUrl);
        }
        config
          ..['url'] = draft.url!.trim()
          ..['headers'] = draft.headers;
    }
    return _database.transaction(() async {
      final lower = name.toLowerCase();
      final names =
          await (_database.selectOnly(_database.mcpServersTable)
                ..addColumns([_database.mcpServersTable.name]))
              .map((r) => r.read(_database.mcpServersTable.name)!)
              .get();
      if (names.any((existing) => existing.toLowerCase() == lower)) {
        throw const InvalidMcpServerException(McpServerProblem.duplicateName);
      }
      final row = await _database
          .into(_database.mcpServersTable)
          .insertReturning(
            McpServersTableCompanion.insert(
              name: name,
              transport: draft.transport.name,
              config: jsonEncode(config),
            ),
          );
      return _fromRow(row, const {});
    });
  }

  @override
  Future<void> remove(String id) async {
    final rowId = _userRowId(id);
    await _database.transaction(() async {
      await (_database.delete(_database.mcpServersTable)..where((t) => t.id.equals(rowId))).go();
      await (_database.delete(
        _database.mcpServerStatesTable,
      )..where((t) => t.serverKey.equals(id))).go();
    });
  }

  /// The `mcp_servers.id` of the user's server [id]; a built-in or unknown id is an [ArgumentError].
  int _userRowId(String id) {
    final rowId = id.startsWith('user:') ? int.tryParse(id.substring('user:'.length)) : null;
    if (rowId == null) {
      throw ArgumentError.value(id, 'id', 'Only a server the user added can be changed');
    }
    return rowId;
  }

  // --- Enablement ---

  @override
  Future<void> setEnabled(String id, {required bool enabled, int? projectId}) async {
    if (projectId == null) {
      final rowId = _userRowId(id);
      await (_database.update(
        _database.mcpServersTable,
      )..where((t) => t.id.equals(rowId))).write(McpServersTableCompanion(enabled: Value(enabled)));
      return;
    }
    final isBuiltin = id == _appKey || id == _dartKey;
    if (!isBuiltin) _userRowId(id);
    final table = _database.mcpServerStatesTable;
    if (enabled) {
      await (_database.delete(
        table,
      )..where((t) => t.serverKey.equals(id) & t.projectId.equals(projectId))).go();
    } else {
      await _database
          .into(table)
          .insert(
            McpServerStatesTableCompanion.insert(
              serverKey: id,
              projectId: projectId,
              enabled: false,
            ),
            mode: InsertMode.insertOrReplace,
          );
    }
  }

  // --- Import ---

  @override
  Future<({List<String> added, List<(String name, String reason)> skipped})> importMcpJson(
    String path,
  ) async {
    final parsed = parseMcpJson(await File(path).readAsString());
    final added = <String>[];
    final skipped = [...parsed.skipped];
    for (final draft in parsed.servers) {
      try {
        await add(draft);
        added.add(draft.name);
      } on InvalidMcpServerException catch (error) {
        skipped.add((
          draft.name,
          error.problem == McpServerProblem.duplicateName ? 'name is taken' : error.problem.name,
        ));
      }
    }
    return (added: added, skipped: skipped);
  }
}
