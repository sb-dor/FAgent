import 'dart:async';
import 'dart:io';

import 'package:dart_acp_sdk/dart_acp_sdk.dart';
import 'package:flutter_code_agent/src/common/acp/agent_connection.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_preflight.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_probe_result.dart';
import 'package:l/l.dart';

/// Starts an agent connection; [AgentConnection.start] in the app.
typedef AgentConnector = Future<AgentConnection> Function({
  required AgentDefinition definition,
  required ShellEnvironment environment,
  required AgentPermissionHandler onPermissionRequest,
  String? workingDirectory,
  Duration initializeTimeout,
  Future<void>? abort,
});

/// {@template i_agent_probe}
/// Finds out what an agent is and can do by starting it, running ACP `initialize` and stopping
/// it again.
/// {@endtemplate}
abstract interface class IAgentProbe {
  /// Probes [agent]. Never throws: problems are in [AgentProbeResult.failure] and
  /// [AgentProbeResult.notInstalled].
  ///
  /// [authStatusWait] is how long to wait for a sign-in status push after `initialize`
  /// ([Duration.zero]: not at all); `null` keeps the probe's default.
  Future<AgentProbeResult> probe(AgentDefinition agent, {Duration? authStatusWait});

  /// Stops every probe in flight, together with its agent process.
  Future<void> dispose();
}

/// {@macro i_agent_probe}
final class AgentProbeImpl implements IAgentProbe {
  /// {@macro i_agent_probe}
  AgentProbeImpl({
    required this._environment,
    this._timeout = const Duration(seconds: 60),
    this._authStatusWait = const Duration(seconds: 3),
    this._connect = AgentConnection.start,
  });

  final ShellEnvironment _environment;
  final Duration _timeout;
  final Duration _authStatusWait;
  final AgentConnector _connect;
  final Set<_ProbeRun> _runs = <_ProbeRun>{};
  bool _disposed = false;

  @override
  Future<AgentProbeResult> probe(AgentDefinition agent, {Duration? authStatusWait}) async {
    if (_disposed) return const AgentProbeResult(failure: 'probe disposed');
    final run = _ProbeRun();
    _runs.add(run);
    try {
      return await _probe(agent, run, authStatusWait ?? _authStatusWait);
    } on _ProbeCancelled {
      return const AgentProbeResult(failure: 'probe cancelled');
    } on AgentPreflightException catch (error) {
      // The executable is missing, or Node.js is missing or too old.
      return AgentProbeResult(
        notInstalled: true,
        notInstalledReason: error.message,
        notInstalledHint: error.hint,
      );
    } on AgentStartException catch (error) {
      return AgentProbeResult(failure: run.timedOut ? _noAnswer : _firstLine(error));
    } on Object catch (error, stackTrace) {
      l.w('Agents | probing ${agent.id} failed: $error', stackTrace);
      return AgentProbeResult(failure: '$error'.split('\n').first);
    } finally {
      _runs.remove(run);
      await run.finish();
    }
  }

  @override
  Future<void> dispose() {
    _disposed = true;
    return Future.wait(<Future<void>>[for (final run in _runs.toList()) run.cancel()]);
  }

  Future<AgentProbeResult> _probe(
    AgentDefinition agent,
    _ProbeRun run,
    Duration authStatusWait,
  ) async {
    run.startedAt = Stopwatch()..start();
    // The probe never runs a session, so nothing project-specific is needed; the temp
    // directory exists everywhere and keeps `npx` away from a `package.json` of the app.
    final connecting = _connect(
      definition: agent,
      environment: _environment,
      onPermissionRequest: (context) async =>
          RequestPermissionResponse(outcome: const RequestPermissionOutcomeCancelled()),
      workingDirectory: Directory.systemTemp.path,
      initializeTimeout: _timeout,
      abort: run.cancelled.future,
    );
    run.timeoutAfter = _timeout;
    // A connection that opens after the probe ended is closed at once.
    unawaited(
      connecting.then((connection) {
        if (run.finished) {
          unawaited(connection.close());
        } else {
          run.connection = connection;
        }
      }, onError: (Object _) {}),
    );
    final connection = await Future.any(<Future<AgentConnection>>[
      connecting,
      run.cancelled.future.then<AgentConnection>((_) => throw const _ProbeCancelled()),
    ]);
    final result = _parse(connection.initializeResult);
    final authStatus = await _authStatus(connection, run, authStatusWait);
    return authStatus == null ? result : result.copyWith(authStatus: authStatus);
  }

  /// The sign-in status the agent pushes after `initialize` (codex-acp), waiting up to [wait]
  /// for it.
  Future<AcpAuthStatus?> _authStatus(
    AgentConnection connection,
    _ProbeRun run,
    Duration wait,
  ) async {
    var status = connection.authStatus;
    if (status == null && wait > Duration.zero) {
      final update = Completer<void>();
      final subscription = connection.incoming.listen((message) {
        if (parseAuthStatusUpdate(message) != null && !update.isCompleted) update.complete();
      }, onDone: () => update.isCompleted ? null : update.complete());
      try {
        await Future.any(<Future<void>>[
          update.future,
          run.cancelled.future,
          Future<void>.delayed(wait),
        ]);
      } finally {
        await subscription.cancel();
      }
      status = connection.authStatus;
    }
    return status == null ? null : AcpAuthStatus(kind: status.kind, label: status.label);
  }

  static const String _noAnswer = 'no ACP answer to initialize';

  /// First stderr line of the failed start, else the exception's own text.
  static String _firstLine(AgentStartException error) {
    for (final line in error.stderrTail) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return error.message.split('\n').first;
  }

  static AgentProbeResult _parse(Map<String, Object?> initialize) {
    final capabilities = _object(initialize['agentCapabilities']);
    final mcp = _object(capabilities['mcpCapabilities']);
    return AgentProbeResult(
      version: switch (_object(initialize['agentInfo'])['version']) {
        final String version => version,
        _ => null,
      },
      authMethods: <AcpAuthMethod>[
        if (initialize['authMethods'] case final List<Object?> methods)
          for (final method in methods)
            if (_object(method) case {'id': final String id} && final Map<String, Object?> map)
              AcpAuthMethod(
                id: id,
                name: switch (map['name']) {
                  final String name => name,
                  _ => id,
                },
                description: switch (map['description']) {
                  final String description => description,
                  _ => null,
                },
                apiKeyProvider: switch (_object(_object(map['_meta'])['api-key'])['provider']) {
                  final String provider => provider,
                  _ => null,
                },
              ),
      ],
      mcpHttp: mcp['http'] == true,
      mcpSse: mcp['sse'] == true,
      loadSession: capabilities['loadSession'] == true,
      systemPrompt: _object(capabilities['sessionCapabilities'])['systemPrompt'] != null,
      canLogout: _object(capabilities['auth'])['logout'] != null,
      image: _object(capabilities['promptCapabilities'])['image'] == true,
    );
  }

  static Map<String, Object?> _object(Object? value) => switch (value) {
    final Map<Object?, Object?> map => map.cast<String, Object?>(),
    _ => const <String, Object?>{},
  };
}

/// One probe in flight.
final class _ProbeRun {
  /// Completes when [dispose] asks the probe to stop.
  final Completer<void> cancelled = Completer<void>();

  AgentConnection? connection;
  Stopwatch? startedAt;
  Duration? timeoutAfter;
  bool finished = false;

  /// The start ended at or after the time limit.
  bool get timedOut {
    final started = startedAt;
    final limit = timeoutAfter;
    return started != null && limit != null && started.elapsed >= limit;
  }

  Future<void> cancel() async {
    if (!cancelled.isCompleted) cancelled.complete();
    await finish();
  }

  /// Closes the connection, if one opened.
  Future<void> finish() async {
    finished = true;
    final open = connection;
    connection = null;
    await open?.close();
  }
}

final class _ProbeCancelled implements Exception {
  const _ProbeCancelled();
}
