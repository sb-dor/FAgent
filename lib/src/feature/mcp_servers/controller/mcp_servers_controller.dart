import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_servers_repository.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_server.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'mcp_servers_controller.freezed.dart';

@freezed
sealed class McpServersState with _$McpServersState {
  /// Nothing has arrived yet.
  const factory McpServersState.initial() = McpServers$InitialState;

  /// The current [servers]: the built-in ones, then the user's.
  const factory McpServersState.completed({required List<McpServer> servers}) =
      McpServers$CompletedState;

  /// Watching failed with [error]; [servers] is the last list that was known.
  const factory McpServersState.error({required Object error, required List<McpServer> servers}) =
      McpServers$ErrorState;
}

/// Follows the MCP servers in the database.
final class McpServersController extends StateController<McpServersState>
    with SequentialControllerHandler {
  McpServersController({
    required this._repository,
    super.initialState = const McpServersState.initial(),
  });

  final IMcpServersRepository _repository;
  StreamSubscription<List<McpServer>>? _subscription;
  List<McpServer> _servers = const <McpServer>[];

  /// The last known servers; empty before the first list arrives.
  List<McpServer> get servers => _servers;

  /// Starts following the servers. Calling it again changes nothing.
  void watch() => handle(
    () async {
      if (isDisposed || _subscription != null) return;
      _subscription = _subscribe();
    },
    error: (error, stackTrace) async =>
        setState(McpServersState.error(error: error, servers: _servers)),
  );

  /// Follows the servers again after the watch failed.
  void retry() => handle(
    () async {
      if (isDisposed) return;
      await _subscription?.cancel();
      _subscription = null;
      if (isDisposed) return;
      setState(const McpServersState.initial());
      _subscription = _subscribe();
    },
    error: (error, stackTrace) async =>
        setState(McpServersState.error(error: error, servers: _servers)),
  );

  StreamSubscription<List<McpServer>> _subscribe() => _repository.watchServers().listen(
    (servers) => setState(McpServersState.completed(servers: _servers = servers)),
    onError: (Object error) => setState(McpServersState.error(error: error, servers: _servers)),
  );

  @override
  void dispose() {
    _subscription?.cancel().ignore();
    super.dispose();
  }
}
