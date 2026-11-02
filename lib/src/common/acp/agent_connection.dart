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

/// Sign-in state an agent reports in `_auth/status_update`: `kind` is `none`, `account`,
/// `api_key`, `external` or `gateway`; `label` is a human-readable summary such as
/// "ChatGPT Plus".
typedef AgentAuthStatus = ({String kind, String label});

/// Reads an `_auth/status_update` notification; `null` for any other message.
///
/// Drops everything but `kind` and `label` (the notification carries the account's email).
AgentAuthStatus? parseAuthStatusUpdate(RawAcpMessage message) {
  if (message.method != '_auth/status_update') return null;
  final status = message.params?['authStatus'];
  if (status is! Map<Object?, Object?>) return null;
  final kind = status['kind'];
  if (kind is! String) return null;
  return (
    kind: kind,
    label: switch (status['label']) {
      final String label => label,
      _ => '',
    },
  );
}

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
  AgentConnection._(
    this.definition,
    this._process,
    this._connection,
    this._incoming,
    this._stderr,
    this._watch,
    this._authStatusOf,
  );

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
  /// adapter, hence the long default). Completing [abort] while initializing stops
  /// the process and throws [AgentStartException] right away.
  static Future<AgentConnection> start({
    required AgentDefinition definition,
    required ShellEnvironment environment,
    required AgentPermissionHandler onPermissionRequest,
    String? workingDirectory,
    Duration initializeTimeout = const Duration(seconds: 120),
    Future<void>? abort,
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
                // `authStatus` makes codex-acp push `_auth/status_update` after
                // `initialize`.
                meta: AcpJsonObject.fromObject(<String, Object?>{
                  'terminal-auth': true,
                  'authStatus': <String, Object?>{},
                }),
              ),
            )
            .onRequestPermission(onPermissionRequest)
            // Updates are consumed raw from [incoming]; this only marks the
            // notification as handled.
            .onSessionUpdate((_) {});

    // The initialize response passes the tap before anyone else can listen. So does the
    // sign-in status codex-acp pushes right after it, which may arrive before this method
    // returns, so it is kept here.
    final initializeResult = Completer<Map<String, Object?>>();
    AgentAuthStatus? authStatus;
    // Cancelled in [close].
    // ignore: cancel_subscriptions
    final watch = incoming.stream.listen((message) {
      final result = message.result;
      if (!initializeResult.isCompleted && message.isResponse && result != null) {
        if (result.containsKey('agentCapabilities')) initializeResult.complete(result);
      }
      authStatus = parseAuthStatusUpdate(message) ?? authStatus;
    });
    final connection = AgentConnection._(
      definition,
      process,
      client.connect(tapped),
      incoming,
      stderr,
      watch,
      () => authStatus,
    );
    unawaited(process.exitCode.then((_) => connection._alive = false));
    unawaited(
      connection._connection.closed.then(
        (_) => connection._alive = false,
        onError: (Object _) => connection._alive = false,
      ),
    );
    var settled = false;
    final aborted = Completer<void>();
    unawaited(aborted.future.then<void>((_) {}, onError: (Object _) {}));
    unawaited(
      abort?.then((_) {
        if (!settled) aborted.completeError(StateError('start aborted'));
      }),
    );
    try {
      await Future.any<void>(<Future<void>>[
        connection._connection.lifecycle.ready,
        process.exitCode.then<void>((code) => throw StateError('agent exited with code $code')),
        aborted.future,
      ]).timeout(initializeTimeout);
      connection.initializeResult = initializeResult.isCompleted
          ? await initializeResult.future
          : const <String, Object?>{};
      return connection;
    } on Object catch (error) {
      await connection.close();
      throw AgentStartException(
        error is TimeoutException
            ? '${definition.displayName} did not initialize within ${initializeTimeout.inSeconds} s'
            : '${definition.displayName} failed to start: $error',
        stderrTail: stderr.items,
      );
    } finally {
      settled = true;
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

  /// Raw `initialize` result: `agentCapabilities`, `authMethods`, `agentInfo`.
  late final Map<String, Object?> initializeResult;

  final GroupedProcess _process;
  final AcpClientConnection _connection;
  final StreamController<RawAcpMessage> _incoming;
  final RingBuffer<String> _stderr;
  final StreamSubscription<RawAcpMessage> _watch;
  final AgentAuthStatus? Function() _authStatusOf;

  /// The last `_auth/status_update` the agent pushed (codex-acp does after `initialize`, to
  /// clients that advertise `_meta.authStatus`), or `null` when it sent none yet.
  ///
  /// Only `kind` and `label` are kept: the notification also carries the account (the user's
  /// email), which the app must neither store nor log.
  AgentAuthStatus? get authStatus => _authStatusOf();

  /// Every incoming message, raw, in wire order. Broadcast; closes when the
  /// agent's stdout ends.
  Stream<RawAcpMessage> get incoming => _incoming.stream;

  /// Typed client → agent requests (`createSession`, `sendPrompt`, …).
  AcpClientContext get agent => _connection.agent;

  /// Last stderr lines of the agent.
  List<String> get stderrTail => _stderr.items;

  /// Completes when the agent process exits.
  Future<int> get exitCode => _process.exitCode;

  bool _alive = true;

  /// `false` once the process exited or the connection closed.
  bool get isAlive => _alive;

  /// Closes the connection and stops the process group.
  ///
  /// The Claude adapter does not exit on stdin EOF (measured with 0.96.0) but
  /// shuts down cleanly on SIGTERM within a second, together with the MCP
  /// servers it started, so the EOF wait is short.
  Future<void> close({Duration gracePeriod = const Duration(seconds: 5)}) async {
    _alive = false;
    unawaited(_watch.cancel());
    _connection.close();
    await _process.stop(exitAfterEof: const Duration(milliseconds: 300), gracePeriod: gracePeriod);
  }
}
