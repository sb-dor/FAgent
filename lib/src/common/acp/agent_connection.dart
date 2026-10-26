import 'dart:async';

import 'package:dart_acp_sdk/dart_acp_sdk.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_preflight.dart';
import 'package:flutter_code_agent/src/common/acp/raw_acp_message.dart';
import 'package:flutter_code_agent/src/common/process/bounded_line_splitter.dart';
import 'package:flutter_code_agent/src/common/process/grouped_process.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:l/l.dart';

/// Answers `session/request_permission`. Must complete exactly once.
typedef AgentPermissionHandler = Future<RequestPermissionResponse> Function(
  AcpClientRequestContext<RequestPermissionRequest> context,
);

/// {@template agent_start_exception}
/// The agent process started but did not finish ACP initialization.
/// {@endtemplate}
final class AgentStartException implements Exception {
  /// {@macro agent_start_exception}
  const AgentStartException(this.message, {this.stderrTail = const <String>[]});

  /// What failed.
  final String message;

  /// Last stderr lines of the agent, for the error screen.
  final List<String> stderrTail;

  @override
  String toString() => 'AgentStartException: $message';
}

/// {@template agent_connection}
/// One running ACP agent process and its initialized client connection.
///
/// The process runs in its own process group ([GroupedProcess]). Every
/// incoming message is published on [incoming] as raw JSON before the SDK
/// decodes it, so the journal keeps messages the SDK does not understand.
/// {@endtemplate}
final class AgentConnection {
  AgentConnection._(this.definition, this._process, this._connection, this._incoming, this._stderr);

  /// Client implementation sent in `initialize`.
  static final Implementation implementation = Implementation(
    name: 'flutter_code_agent',
    version: '0.1.0',
  );

  /// Starts [definition] and initializes ACP.
  ///
  /// Throws [AgentPreflightException] before spawning when the machine cannot
  /// run the agent, and [AgentStartException] when initialization fails or
  /// takes longer than [initializeTimeout] (the first `npx` run downloads the
  /// adapter, hence the long default).
  static Future<AgentConnection> start({
    required AgentDefinition definition,
    required ShellEnvironment environment,
    required AgentPermissionHandler onPermissionRequest,
    String? workingDirectory,
    Duration initializeTimeout = const Duration(seconds: 120),
  }) async {
    final executable = await AgentPreflight.check(definition, environment);
    final process = await GroupedProcess.start(
      executable,
      definition.arguments,
      environment: <String, String>{...environment.variables, ...definition.environment},
      workingDirectory: workingDirectory,
    );
    final stderr = RingBuffer<String>(500);
    process.stderrLines.listen((line) {
      stderr.add(line);
      l.v5('Agent ${definition.id} | stderr | $line');
    });

    final incoming = StreamController<RawAcpMessage>.broadcast(sync: true);
    final wire = ndJsonStream(
      output: AcpWritable<List<int>>.fromStreamSink(process.stdin),
      input: process.stdout,
    );
    final tapped = AcpDuplexStream<Object?>(
      readable: wire.readable.transform(
        StreamTransformer<Object?, Object?>.fromHandlers(
          handleData: (value, sink) {
            _publish(incoming, value);
            sink.add(value);
          },
          handleDone: (sink) {
            incoming.close();
            sink.close();
          },
        ),
      ),
      writable: wire.writable,
    );

    final client =
        AcpClientApp.v1(
              implementation: implementation,
              capabilities: ClientCapabilities(
                fs: FileSystemCapabilities(readTextFile: false, writeTextFile: false),
                terminal: false,
                // The adapter advertises its login methods only to clients that
                // can run terminal auth; ClientCapabilities has no `auth` field.
                meta: AcpJsonObject.fromObject(<String, Object?>{'terminal-auth': true}),
              ),
            )
            .onRequestPermission(onPermissionRequest)
            // Updates are consumed raw from [incoming]; this only marks the
            // notification as handled.
            .onSessionUpdate((_) {});

    final connection = AgentConnection._(
      definition,
      process,
      client.connect(tapped),
      incoming,
      stderr,
    );
    try {
      await Future.any<void>(<Future<void>>[
        connection._connection.lifecycle.ready,
        process.exitCode.then<void>((code) => throw StateError('agent exited with code $code')),
      ]).timeout(initializeTimeout);
      return connection;
    } on Object catch (error) {
      await connection.close();
      throw AgentStartException(
        error is TimeoutException
            ? '${definition.displayName} did not initialize within ${initializeTimeout.inSeconds} s'
            : '${definition.displayName} failed to start: $error',
        stderrTail: stderr.items,
      );
    }
  }

  static void _publish(StreamController<RawAcpMessage> incoming, Object? value) {
    if (incoming.isClosed) return;
    for (final item in value is List<Object?> ? value : <Object?>[value]) {
      if (item is Map<Object?, Object?>) incoming.add(RawAcpMessage(item.cast<String, Object?>()));
    }
  }

  /// The agent this connection runs.
  final AgentDefinition definition;

  final GroupedProcess _process;
  final AcpClientConnection _connection;
  final StreamController<RawAcpMessage> _incoming;
  final RingBuffer<String> _stderr;

  /// Every incoming message, raw, in wire order. Broadcast; closes when the
  /// agent's stdout ends.
  Stream<RawAcpMessage> get incoming => _incoming.stream;

  /// Typed client → agent requests (`createSession`, `sendPrompt`, …).
  AcpClientContext get agent => _connection.agent;

  /// Last stderr lines of the agent.
  List<String> get stderrTail => _stderr.items;

  /// Completes when the agent process exits.
  Future<int> get exitCode => _process.exitCode;

  /// Closes the connection and stops the process group: stdin EOF first (the
  /// adapter shuts its sessions down), then SIGTERM, then SIGKILL.
  Future<void> close({Duration gracePeriod = const Duration(seconds: 5)}) async {
    _connection.close();
    await _process.stop(gracePeriod: gracePeriod);
  }
}
