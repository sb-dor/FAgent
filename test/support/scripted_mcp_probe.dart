import 'dart:async';

import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_probe.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_server.dart';

/// An [IMcpProbe] that answers from [results] by server id (by default [fallback]) and records
/// every server it was asked about, so tests never start a process or open a connection.
///
/// A server in [held] is not answered until [release] is called for it.
final class ScriptedMcpProbe implements IMcpProbe {
  /// Creates the probe.
  ScriptedMcpProbe({
    Map<String, McpProbeResult>? results,
    this.fallback = const McpProbeFailed('Not scripted'),
  }) : results = results ?? <String, McpProbeResult>{};

  /// What each server answers.
  final Map<String, McpProbeResult> results;

  /// What a server without an entry in [results] answers.
  McpProbeResult fallback;

  /// The servers probed so far, in order.
  final List<McpServer> probed = <McpServer>[];

  /// The ids of [probed].
  List<String> get probedIds => [for (final server in probed) server.id];

  /// The ids that wait for [release].
  final Set<String> held = <String>{};

  final Map<String, Completer<void>> _gates = <String, Completer<void>>{};

  /// How often [dispose] was called.
  int disposed = 0;

  @override
  Future<void> dispose() async => disposed++;

  /// Lets a held probe of [id] answer.
  void release(String id) => _gates[id]?.complete();

  @override
  Future<McpProbeResult> probe(
    McpServer server, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    probed.add(server);
    if (held.contains(server.id)) await (_gates[server.id] ??= Completer<void>()).future;
    return results[server.id] ?? fallback;
  }
}
