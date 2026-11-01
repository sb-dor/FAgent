import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_server.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_executable.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/flutter_sdk_repository.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/dart_mcp_command.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_json.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_probe.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_exceptions.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_server.dart';

/// The MCP servers handed to agents: the app's built-in ones and the user's own.
abstract interface class IMcpServersRepository {
  /// The built-in servers, then the user's by creation time; again whenever any of them, the
  /// per-project switches or what [check] found change. Cancel the subscription to stop watching.
  ///
  /// The app's server shows the address it listens on and its tool count, or why it did not start.
  /// Dart MCP and the user's servers show `unknown` until [check] has probed them.
  Stream<List<McpServer>> watchServers();

  /// Connects to Dart MCP and the user's servers that are switched on everywhere, or only to [id]
  /// when it is one of them, and keeps what it found in memory for [watchServers].
  ///
  /// Dart MCP runs on the Flutter SDK of Settings; without one it is `failed` with
  /// [mcpSdkNotFoundError]. A server that is already being checked is not checked again; the call
  /// waits for that check. The app's own server is never probed. A server that does not work is
  /// its status, not an error.
  Future<void> check({String? id});

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

/// Names the built-in servers go by, so a user's server must not use them. The display name
/// `Dart MCP` needs no entry: its space already fails [_validName].
const Set<String> _reservedNames = {'flutter_code_agent', 'dart'};

/// [IMcpServersRepository] over the `mcp_servers` and `mcp_server_states` tables.
final class McpServersRepositoryImpl implements IMcpServersRepository {
  /// Creates the repository. [flutterSdk] tells which Flutter SDK Dart MCP runs on (the one the
  /// Flutter section of Settings shows); [probe] connects to the servers.
  McpServersRepositoryImpl({
    required this._database,
    required this._appServer,
    required this._probe,
    required this._flutterSdk,
  });

  final AppDatabase _database;
  final IAppMcpServer _appServer;
  final IMcpProbe _probe;
  final IFlutterSdkRepository _flutterSdk;

  /// What the probes found, by server id; lost when the app closes.
  final Map<String, McpProbeResult> _results = <String, McpProbeResult>{};

  /// The probes that are running, by server id.
  final Map<String, Future<void>> _probing = <String, Future<void>>{};

  /// Tells [watchServers] that [_results] or the Dart MCP SDK changed.
  final StreamController<void> _changed = StreamController<void>.broadcast(sync: true);

  /// Whether the Flutter SDK was looked up, and the folder it was found in.
  bool _sdkLookedUp = false;
  String? _dartSdkRoot;

  @override
  Stream<List<McpServer>> watchServers() {
    final controller = StreamController<List<McpServer>>();
    StreamSubscription<List<McpServerRow>>? rowsSubscription;
    StreamSubscription<List<McpServerStateRow>>? statesSubscription;
    StreamSubscription<void>? changesSubscription;
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
        changesSubscription = _changed.stream.listen((_) => emit());
      }
      ..onCancel = () async {
        await rowsSubscription?.cancel();
        await statesSubscription?.cancel();
        await changesSubscription?.cancel();
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
      for (final row in rows)
        _applyResult(
          _fromRow(row, disabled['user:${row.id}'] ?? const {}),
          // A server that is off is not connected to, so an older result says nothing.
          row.enabled ? _results['user:${row.id}'] : null,
        ),
    ];
  }

  McpServer _builtinApp(Set<int> disabledIn) {
    final url = _appServer.url;
    final startError = _appServer.startError;
    return McpServer(
      id: _appKey,
      name: 'flutter_code_agent',
      transport: McpTransport.http,
      url: url?.toString(),
      builtin: true,
      disabledIn: disabledIn,
      status: url != null
          ? McpStatus.ready
          : startError != null
          ? McpStatus.failed
          : McpStatus.unknown,
      toolCount: url != null ? _appServer.toolCount : null,
      error: url == null && startError != null ? '$startError' : null,
    );
  }

  McpServer _builtinDart(Set<int> disabledIn) {
    final server = McpServer(
      id: _dartKey,
      name: 'Dart MCP',
      transport: McpTransport.stdio,
      builtin: true,
      disabledIn: disabledIn,
    );
    if (!_sdkLookedUp) return server;
    final sdk = _dartSdkRoot;
    if (sdk == null) return server.copyWith(status: McpStatus.failed, error: mcpSdkNotFoundError);
    final (:command, :args) = dartMcpCommand(sdk);
    return _applyResult(server.copyWith(command: command, args: args), _results[_dartKey]);
  }

  McpServer _applyResult(McpServer server, McpProbeResult? result) => switch (result) {
    null => server,
    McpProbeConnected(:final toolCount) => server.copyWith(
      status: McpStatus.ready,
      toolCount: toolCount,
    ),
    McpProbeFailed(:final message) => server.copyWith(status: McpStatus.failed, error: message),
    McpProbeNeedsAuth() => server.copyWith(status: McpStatus.needsAuth),
  };

  // --- Checking ---

  @override
  Future<void> check({String? id}) async {
    final checks = <Future<void>>[];
    if (id == null || id == _dartKey) checks.add(_checkDart());
    if (id == null || id.startsWith('user:')) {
      final rows = await _database.select(_database.mcpServersTable).get();
      for (final row in rows) {
        final serverId = 'user:${row.id}';
        if (row.enabled && (id == null || id == serverId)) {
          checks.add(_probeOnce(_fromRow(row, const {})));
        }
      }
    }
    await Future.wait(checks);
  }

  /// Looks up the SDK of Settings, then probes Dart MCP on it.
  Future<void> _checkDart() async {
    final flutter = (await _flutterSdk.sdkFor(null)).path;
    final root = flutter == null ? null : flutterSdkRootOf(flutter);
    if (!_sdkLookedUp || root != _dartSdkRoot) {
      _sdkLookedUp = true;
      _dartSdkRoot = root;
      if (root == null) _results.remove(_dartKey);
      _changed.add(null);
    }
    if (root == null) return;
    final (:command, :args) = dartMcpCommand(root);
    await _probeOnce(
      McpServer(
        id: _dartKey,
        name: 'Dart MCP',
        transport: McpTransport.stdio,
        command: command,
        args: args,
        builtin: true,
      ),
    );
  }

  Future<void> _probeOnce(McpServer server) => _probing[server.id] ??= (() async {
    try {
      _results[server.id] = await _probe.probe(server);
    } on Object catch (error) {
      _results[server.id] = McpProbeFailed('$error');
    } finally {
      _probing.remove(server.id);
    }
    _changed.add(null);
  })();

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
  Future<McpServer> add(McpServerDraft draft) async {
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
    _results.remove(id);
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
    final String text;
    try {
      text = await File(path).readAsString();
    } on FileSystemException catch (error) {
      throw McpJsonException('cannot read the file: ${error.message}');
    } on FormatException catch (error) {
      throw McpJsonException('not UTF-8 text: ${error.message}');
    }
    final parsed = parseMcpJson(text);
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
