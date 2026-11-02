import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/process/grouped_process.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_server.dart';
import 'package:l/l.dart';
import 'package:mcp_dart/mcp_dart.dart' hide McpServer;

/// What connecting to an MCP server showed.
@immutable
sealed class McpProbeResult {
  const McpProbeResult();
}

/// The server answered `initialize` and `tools/list`.
final class McpProbeConnected extends McpProbeResult {
  /// Creates the result.
  const McpProbeConnected(this.toolCount);

  /// How many tools the server lists.
  final int toolCount;

  @override
  bool operator ==(Object other) => other is McpProbeConnected && other.toolCount == toolCount;

  @override
  int get hashCode => Object.hash(McpProbeConnected, toolCount);

  @override
  String toString() => 'McpProbeConnected($toolCount)';
}

/// The server could not be reached or did not behave like an MCP server.
final class McpProbeFailed extends McpProbeResult {
  /// Creates the result.
  const McpProbeFailed(this.message);

  /// Why, in English and in one line.
  final String message;

  @override
  bool operator ==(Object other) => other is McpProbeFailed && other.message == message;

  @override
  int get hashCode => Object.hash(McpProbeFailed, message);

  @override
  String toString() => 'McpProbeFailed($message)';
}

/// The server answered 401: the user has to sign in.
final class McpProbeNeedsAuth extends McpProbeResult {
  /// Creates the result.
  const McpProbeNeedsAuth();

  @override
  bool operator ==(Object other) => other is McpProbeNeedsAuth;

  @override
  int get hashCode => (McpProbeNeedsAuth).hashCode;

  @override
  String toString() => 'McpProbeNeedsAuth()';
}

/// Connects to an MCP server to see whether it works and what it offers.
abstract interface class IMcpProbe {
  /// Starts or reaches [server], asks it to `initialize` and list its tools, then disconnects
  /// (a `stdio` server's whole process group is killed). Never throws: every problem, a [timeout]
  /// included (`Timed out`), is a [McpProbeFailed].
  Future<McpProbeResult> probe(McpServer server, {Duration timeout = const Duration(seconds: 10)});

  /// Kills the process group of every `stdio` probe in flight (each of those probes completes with
  /// a [McpProbeFailed]) and makes later probes fail at once with `Stopped`, without starting
  /// anything. Call it when the app quits, so no server outlives it.
  Future<void> dispose();
}

/// Starts [executable] in its own process group: [GroupedProcess.start].
typedef GroupedProcessStart = Future<GroupedProcess> Function(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  Duration startTimeout,
});

/// {@template mcp_probe}
/// [IMcpProbe] over the `mcp_dart` client with the `initialize` / `tools/list` flow of Claude Code.
///
/// A `stdio` server runs in its own process group ([GroupedProcess]) with the login shell's
/// environment plus its own `env`; an `http` server gets its configured headers.
/// {@endtemplate}
final class McpProbeImpl implements IMcpProbe {
  /// {@macro mcp_probe}
  ///
  /// `start` starts a `stdio` server; [GroupedProcess.start] by default.
  McpProbeImpl({required this._environment, this._start = GroupedProcess.start});

  final ShellEnvironment _environment;
  final GroupedProcessStart _start;

  /// The process groups of the `stdio` probes in flight.
  final Set<GroupedProcess> _running = <GroupedProcess>{};

  /// The `stdio` probes whose process is still starting; each completes once its process runs, or
  /// is stopped when [dispose] came during the start.
  final Set<Future<void>> _starting = <Future<void>>{};
  bool _disposed = false;

  static const McpClientOptions _clientOptions = McpClientOptions(protocol: McpProtocol.legacy);

  /// The longest message kept of a failure.
  static const int _maxMessage = 300;

  @override
  Future<McpProbeResult> probe(
    McpServer server, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_disposed) return const McpProbeFailed('Stopped');
    final deadline = Stopwatch()..start();
    try {
      return switch (server.transport) {
        McpTransport.stdio => await _probeStdio(server, timeout),
        McpTransport.http => await _probeHttp(server, timeout),
      };
    } on Object catch (error, stackTrace) {
      l.w(
        'MCP probe | ${server.name} failed after ${deadline.elapsedMilliseconds} ms: $error',
        stackTrace,
      );
      return McpProbeFailed(_oneLine('$error'));
    }
  }

  Future<McpProbeResult> _probeStdio(McpServer server, Duration timeout) async {
    final command = server.command?.trim() ?? '';
    if (command.isEmpty) return const McpProbeFailed('No command');
    final starting = Completer<void>();
    _starting.add(starting.future);
    final GroupedProcess process;
    try {
      try {
        process = await _start(
          command,
          server.args,
          environment: <String, String>{..._environment.variables, ...server.env},
          startTimeout: timeout,
        );
      } on Object catch (error) {
        return McpProbeFailed(_oneLine('Cannot start $command: $error'));
      }
      _running.add(process);
      if (_disposed) {
        // Disposed while the process was starting; dispose waits for this.
        await _stop(process);
        _running.remove(process);
        return const McpProbeFailed('Stopped');
      }
    } finally {
      _starting.remove(starting.future);
      starting.complete();
    }
    final stderrTail = <String>[];
    final stderrSubscription = process.stderrLines.listen((line) {
      if (line.trim().isEmpty) return;
      stderrTail.add(line.trim());
      if (stderrTail.length > 3) stderrTail.removeAt(0);
    });
    final transport = _GroupedStdioTransport(process);
    try {
      final result = await _listTools(transport, timeout);
      if (result is McpProbeFailed && stderrTail.isNotEmpty) {
        return McpProbeFailed(_oneLine('${result.message}: ${stderrTail.join(' ')}'));
      }
      return result;
    } finally {
      // The group is killed whether the probe ended, failed or ran out of time.
      await _stop(process);
      _running.remove(process);
      await stderrSubscription.cancel();
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await Future.wait(<Future<void>>[
      // A probe still starting stops its own process once it runs: it sees [_disposed].
      ..._starting,
      for (final process in _running.toList()) _stop(process),
    ]);
  }

  static Future<void> _stop(GroupedProcess process) => process.stop(
    exitAfterEof: const Duration(milliseconds: 200),
    gracePeriod: const Duration(seconds: 2),
  );

  Future<McpProbeResult> _probeHttp(McpServer server, Duration timeout) async {
    final url = Uri.tryParse(server.url?.trim() ?? '');
    if (url == null || !url.hasScheme || url.host.isEmpty) return const McpProbeFailed('No URL');
    final transport = StreamableHttpClientTransport(
      url,
      opts: StreamableHttpClientTransportOptions(
        requestInit: <String, dynamic>{
          if (server.headers.isNotEmpty) 'headers': <String, dynamic>{...server.headers},
        },
      ),
    );
    return _listTools(transport, timeout);
  }

  /// Connects [transport], lists the tools of every page and closes the client.
  Future<McpProbeResult> _listTools(Transport transport, Duration timeout) async {
    final client = McpClient(
      const Implementation(name: 'flutter_code_agent', version: '1.0.0'),
      options: _clientOptions,
    );
    try {
      return await (() async {
        await client.connect(transport);
        var count = 0;
        String? cursor;
        do {
          final page = await client.listTools(
            params: cursor == null ? null : ListToolsRequest(cursor: cursor),
          );
          count += page.tools.length;
          cursor = page.nextCursor;
        } while (cursor != null);
        return McpProbeConnected(count) as McpProbeResult;
      })().timeout(timeout);
    } on Object catch (error) {
      return switch (error) {
        TimeoutException() => const McpProbeFailed('Timed out'),
        UnauthorizedError() => const McpProbeNeedsAuth(),
        McpError(:final message) when message.contains('HTTP 401') => const McpProbeNeedsAuth(),
        McpError(:final message) => McpProbeFailed(_oneLine(message)),
        _ => McpProbeFailed(_oneLine('$error')),
      };
    } finally {
      // Closing must not outlast the probe: a server that hangs is killed by its caller.
      unawaited(
        client.close().timeout(const Duration(seconds: 2)).then<void>((_) {}, onError: (_) {}),
      );
    }
  }

  static String _oneLine(String text) {
    final line = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return line.length <= _maxMessage ? line : '${line.substring(0, _maxMessage)}…';
  }
}

/// The client side of MCP over the stdin and stdout of a [GroupedProcess]: one JSON-RPC message
/// per line. The caller owns the process, so [close] does not stop it.
final class _GroupedStdioTransport implements Transport {
  _GroupedStdioTransport(this._process);

  final GroupedProcess _process;
  StreamSubscription<String>? _subscription;
  bool _closed = false;

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  @override
  String? get sessionId => null;

  @override
  Future<void> start() async {
    _subscription = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (line.trim().isEmpty) return;
            try {
              final decoded = jsonDecode(line);
              if (decoded is Map<String, dynamic>)
                onmessage?.call(JsonRpcMessage.fromJson(decoded));
            } on Object {
              // A line that is not a JSON-RPC message (a log line on stdout) is not an answer.
            }
          },
          onDone: () {
            if (!_closed) {
              _closed = true;
              onclose?.call();
            }
          },
        );
  }

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) async {
    if (_closed) throw StateError('The transport is closed');
    try {
      _process.stdin.writeln(jsonEncode(message.toJson()));
      await _process.stdin.flush();
    } on SocketException catch (error) {
      throw StateError('The server closed its input: ${error.message}');
    }
  }

  @override
  Future<void> close() async {
    final wasClosed = _closed;
    _closed = true;
    await _subscription?.cancel();
    if (!wasClosed) onclose?.call();
  }
}
