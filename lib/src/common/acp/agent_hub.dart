import 'dart:async';
import 'dart:convert';

import 'package:dart_acp_sdk/dart_acp_sdk.dart' hide Error;
import 'package:drift/drift.dart' show Value;
import 'package:flutter_code_agent/src/common/acp/agent_auth.dart';
import 'package:flutter_code_agent/src/common/acp/agent_connection.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_preflight.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/permission_broker.dart';
import 'package:flutter_code_agent/src/common/acp/raw_acp_message.dart';
import 'package:flutter_code_agent/src/common/acp/session_event.dart';
import 'package:flutter_code_agent/src/common/acp/session_event_store.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:l/l.dart';

/// Starts an agent; replaced in tests.
typedef AgentConnector = Future<AgentConnection> Function(
  AgentDefinition definition,
  AgentPermissionHandler onPermission,
);

/// Hooks around every turn (the changed-files snapshot uses it).
abstract interface class TurnObserver {
  /// Runs before `session/prompt` is sent; the turn waits for it.
  Future<Object?> beforeTurn(LiveSession session);

  /// Runs after the turn; a non-null result is journaled as a durable
  /// [SessionEventKind.turnFiles] event.
  Future<Map<String, Object?>?> afterTurn(LiveSession session, Object? beforeToken);
}

/// A message for the UI that is not part of any journal (for example a
/// journal write that failed).
final class HubNotice {
  /// Creates a notice.
  const HubNotice(this.sessionId, this.message);

  /// App session it belongs to.
  final int sessionId;

  /// What happened.
  final String message;
}

/// JSON-RPC error code of `authRequired`.
const int kAcpAuthRequiredCode = -32000;

/// JSON-RPC error code of "resource not found" (unknown session on load).
const int kAcpResourceNotFoundCode = -32002;

final class _AgentSlot {
  _AgentSlot(this.definition);

  final AgentDefinition definition;
  AgentConnection? connection;
  Future<AgentConnection>? starting;
  int generation = 0;
  final Map<String, LiveSession> byAcpId = <String, LiveSession>{};
  final Map<String, RawAcpMessage> rawRequests = <String, RawAcpMessage>{};
}

/// {@template agent_hub}
/// Owns the agent processes and every chat's runtime state.
///
/// * One [AgentConnection] per agent, started lazily and single-flight; each
///   start is a new generation and frames of old generations are dropped.
/// * Per chat: a setup lane (start, load, new, config, sending a prompt) that
///   runs one operation at a time, and a control lane (stop, permission
///   answers) that runs immediately — waiting for a turn to end never holds
///   the setup lane.
/// * Status changes follow [SessionStatus.canMoveTo]; anything else is
///   rejected with a [StateError], in release builds too.
/// {@endtemplate}
final class AgentHub {
  /// {@macro agent_hub}
  AgentHub({
    required this._database,
    required ShellEnvironment environment,
    Map<String, AgentDefinition>? agents,
    AgentConnector? connector,
    AgentAuth? auth,
    this._observers = const <TurnObserver>[],
    this.setupTimeout = const Duration(seconds: 60),
    this.cancelTimeout = const Duration(seconds: 15),
  }) : auth = auth ?? AgentAuth(environment: environment),
       _slots = <String, _AgentSlot>{
         for (final MapEntry(:key, :value) in (agents ?? _defaultAgents).entries)
           key: _AgentSlot(value),
       } {
    _connector =
        connector ??
        (definition, onPermission) => AgentConnection.start(
          definition: definition,
          environment: environment,
          onPermissionRequest: onPermission,
        );
  }

  static const Map<String, AgentDefinition> _defaultAgents = <String, AgentDefinition>{
    'claude': AgentDefinition.claude,
  };

  final AppDatabase _database;
  final List<TurnObserver> _observers;
  final Map<String, _AgentSlot> _slots;
  late final AgentConnector _connector;

  /// Login runner shared by all chats.
  final AgentAuth auth;

  /// Pending permission requests.
  final PermissionBroker permissions = PermissionBroker();

  /// Deadline for `session/new` and `session/load`.
  final Duration setupTimeout;

  /// How long Stop may take before force-stop is offered.
  final Duration cancelTimeout;

  final Map<int, Future<LiveSession>> _sessions = <int, Future<LiveSession>>{};
  final Map<int, LiveSession> _opened = <int, LiveSession>{};
  final Map<int, Future<void>> _setupLanes = <int, Future<void>>{};
  final StreamController<HubNotice> _notices = StreamController<HubNotice>.broadcast();
  bool _disposing = false;
  final Set<AgentLogin> _restartAfter = <AgentLogin>{};

  /// Errors that cannot go to a journal.
  Stream<HubNotice> get notices => _notices.stream;

  /// Agents the hub can run.
  Iterable<AgentDefinition> get agents => _slots.values.map((s) => s.definition);

  /// Chats opened so far (chats whose journal failed to open are skipped).
  Future<List<LiveSession>> get liveSessions async => <LiveSession>[
    for (final opening in List<Future<LiveSession>>.of(_sessions.values))
      if (await opening.then<LiveSession?>((s) => s, onError: (Object _) => null)
          case final LiveSession live)
        live,
  ];

  /// The chat's runtime state if it was opened in this run, without opening
  /// it (the sidebar shows statuses without loading every journal).
  LiveSession? opened(int sessionId) => _opened[sessionId];

  /// Chats with a turn or setup in flight.
  Future<List<LiveSession>> busySessions() async =>
      (await liveSessions).where((s) => s.status.value.isBusy).toList();

  // --- Sessions ----------------------------------------------------------------

  /// The runtime state of chat [sessionId], opening its journal on first use.
  Future<LiveSession> session(int sessionId) {
    _checkNotDisposed();
    return _sessions[sessionId] ??= _open(sessionId)
        .catchError((Object error, StackTrace stackTrace) {
          _sessions.remove(sessionId);
          Error.throwWithStackTrace(error, stackTrace);
        });
  }

  Future<LiveSession> _open(int sessionId) async {
    final record = await (_database.select(
      _database.sessionsTable,
    )..where((s) => s.id.equals(sessionId))).getSingle();
    final project = await (_database.select(
      _database.projectsTable,
    )..where((p) => p.id.equals(record.projectId))).getSingle();
    if (!_slots.containsKey(record.agentId)) {
      throw StateError('Session $sessionId uses unknown agent ${record.agentId}');
    }
    return _opened[sessionId] = LiveSession(
      id: sessionId,
      agentId: record.agentId,
      cwd: project.path,
      store: await SessionEventStore.open(_database, sessionId),
      acpSessionId: record.acpSessionId,
    );
  }

  // --- Prompt, stop, retry ---------------------------------------------------------

  /// Sends a text prompt and completes when the turn ends.
  ///
  /// Allowed in `cold`, `idle` and `error` (an error restarts the agent). The
  /// prompt is journaled before it is sent; if that write fails nothing is sent.
  Future<void> prompt(
    int sessionId,
    String text, {
    List<Map<String, Object?>> resources = const [],
  }) async {
    final live = await session(sessionId);
    await _setupLane(live, () async {
      final status = live.status.value;
      if (status != SessionStatus.cold &&
          status != SessionStatus.idle &&
          status != SessionStatus.error) {
        throw StateError('Cannot send a prompt while the session is ${status.name}');
      }
      live
        ..lastPrompt = <Map<String, Object?>>[
          <String, Object?>{'type': 'text', 'text': text},
          ...resources,
        ]
        ..canRetryPrompt.value = false;
      await _ensureReady(live);
      if (live.status.value != SessionStatus.idle) {
        throw StateError('The agent stopped while the session was being prepared');
      }
      // Reserve the turn before leaving the lane: a second prompt now sees
      // `running` and is rejected.
      _move(live, SessionStatus.running);
    });
    await _runTurn(live, text);
  }

  /// Repeats the last prompt after a login.
  Future<void> retryPrompt(int sessionId) async {
    final live = await session(sessionId);
    final last = live.lastPrompt;
    if (last == null || !live.canRetryPrompt.value) throw StateError('No prompt to repeat');
    final text = last.first['text']! as String;
    await prompt(sessionId, text, resources: last.skip(1).toList());
  }

  Future<void> _runTurn(LiveSession live, String text) async {
    final turn = Completer<void>();
    live.turn = turn.future;
    final tokens = <Object?>[];
    var sent = false;
    try {
      for (final observer in _observers) {
        tokens.add(
          await observer.beforeTurn(live).catchError((Object error) {
            l.w('AgentHub | turn observer failed before the turn: $error');
            return null;
          }),
        );
      }
      // Preparation can be overtaken by Stop or by the agent stopping.
      if (live.status.value != SessionStatus.running) return;
      final connection = _slots[live.agentId]!.connection;
      if (connection == null || !connection.isAlive) {
        await _failOnce(
          live,
          const SessionProblem(
            SessionProblemKind.crash,
            'The agent stopped before the prompt was sent',
          ),
        );
        return;
      }
      final request = PromptRequest.fromJson(<String, Object?>{
        'sessionId': live.acpSessionId,
        'prompt': live.lastPrompt,
      });
      // Durable before sending: a crash after this point still shows the
      // prompt. If the write fails nothing is sent (the catch below reports it).
      await live.store.addDurable(
        SessionEventOrigin.user,
        SessionEventKind.prompt,
        _plain(request.toJson()),
      );
      if (live.status.value != SessionStatus.running) return;
      unawaited(
        _touchSession(
          live,
          title: text,
        ).catchError((Object error) => l.w('AgentHub | could not update the chat title: $error')),
      );
      sent = true;
      final response = await connection.agent.sendPrompt(request);
      await live.store
          .addDurable(SessionEventOrigin.app, SessionEventKind.system, <String, Object?>{
            'type': 'turn_end',
            'stopReason': response.stopReason.toJson(),
          })
          .then<void>(
            (_) {},
            onError: (Object error) => _notice(live, 'Could not save the turn end: $error'),
          );
      _endTurn(live);
    } on JsonRpcRequestException catch (error) {
      if (error.error.code == kAcpAuthRequiredCode && live.status.value == SessionStatus.running) {
        live
          ..interrupted = SessionOperation.prompt
          ..problem.value = SessionProblem(SessionProblemKind.auth, error.error.message);
        _move(live, SessionStatus.needsAuth);
      } else {
        await _failOnce(live, SessionProblem(SessionProblemKind.transient, error.error.message));
      }
    } on Object catch (error) {
      await _failOnce(live, SessionProblem(SessionProblemKind.transient, '$error'));
    } finally {
      // Stop arrived before the prompt went out: nothing to wait for.
      if (!sent && live.status.value == SessionStatus.cancelling) _move(live, SessionStatus.idle);
      live
        ..cancelTimer?.cancel()
        ..cancelTimer = null
        ..canForceStop.value = false;
      if (live.problem.value?.kind == SessionProblemKind.stuck) live.problem.value = null;
      permissions.cancelSession(live.id, 'turn ended');
      await live.store.flush().catchError((Object _) {});
      for (final (index, token) in tokens.indexed) {
        final result = await _observers[index].afterTurn(live, token).catchError((Object error) {
          l.w('AgentHub | turn observer failed: $error');
          return null;
        });
        if (result != null && !live.store.isClosed) {
          await live.store
              .addDurable(SessionEventOrigin.app, SessionEventKind.turnFiles, result)
              .then<void>(
                (_) {},
                onError: (Object error) => _notice(live, 'Could not save changed files: $error'),
              );
        }
      }
      live.turn = null;
      turn.complete();
    }
  }

  /// The turn ended: back to `idle` unless something else (an error, a
  /// shutdown) already took the session.
  void _endTurn(LiveSession live) {
    switch (live.status.value) {
      case SessionStatus.running || SessionStatus.awaitingPermission || SessionStatus.cancelling:
        _move(live, SessionStatus.idle);
      default:
        break;
    }
  }

  /// Stops the running turn (control lane: never waits for the setup lane).
  Future<void> cancel(int sessionId) async {
    final live = await session(sessionId);
    final status = live.status.value;
    if (status != SessionStatus.running && status != SessionStatus.awaitingPermission) return;
    _move(live, SessionStatus.cancelling);
    permissions.cancelSession(live.id, 'turn cancelled');
    final connection = _slots[live.agentId]!.connection;
    final acpId = live.acpSessionId;
    if (connection != null && acpId != null) {
      await connection.agent.cancelSession(CancelNotification(sessionId: SessionId(acpId)));
    }
    live.cancelTimer?.cancel();
    live.cancelTimer = Timer(cancelTimeout, () {
      if (live.status.value != SessionStatus.cancelling) return;
      live
        ..canForceStop.value = true
        ..problem.value = const SessionProblem(
          SessionProblemKind.stuck,
          'The agent does not stop. Force-stopping kills the agent process for every chat that uses it.',
        );
    });
  }

  /// Kills [agentId]'s process; its busy chats go to `error`.
  Future<void> forceStop(String agentId) =>
      _closeConnection(_slots[agentId]!, reason: 'Stopped by you');

  /// Repeats the failed setup, or restarts the agent after an error.
  Future<void> retry(int sessionId) async {
    final live = await session(sessionId);
    final status = live.status.value;
    if (status != SessionStatus.setupFailed && status != SessionStatus.error) {
      throw StateError('Nothing to retry while the session is ${status.name}');
    }
    await _setupLane(live, () => _ensureReady(live));
  }

  /// Destructive: forgets the agent session and creates a new one (the agent
  /// loses the chat's context; the journal stays).
  Future<void> startNewAgentSession(int sessionId) async {
    final live = await session(sessionId);
    if (live.status.value != SessionStatus.setupFailed) {
      throw StateError('A new agent session is only offered after a failed load');
    }
    await _setupLane(live, () async {
      final connection = await _start(live);
      final lost = live.acpSessionId;
      await _create(live, connection, contextLostFrom: lost);
    });
  }

  /// Sets a config option (mode, model, …) of a live chat.
  Future<void> setConfigOption(int sessionId, String configId, Object value) async {
    final live = await session(sessionId);
    await _setupLane(live, () async {
      final connection = _slots[live.agentId]!.connection;
      final acpId = live.acpSessionId;
      if (connection == null || acpId == null) throw StateError('The session is not live');
      final response = await connection.agent.setSessionConfigOption(
        SetSessionConfigOptionRequest.fromJson(<String, Object?>{
          'sessionId': acpId,
          'configId': configId,
          if (value is bool) ...<String, Object?>{'type': 'boolean', 'value': value} else
            'value': '$value',
        }),
      );
      live.configOptions.value = _objects(_plain(response.toJson())['configOptions']);
    });
  }

  /// Records that the user allowed `bypassPermissions` in chat [sessionId].
  Future<void> acknowledgeBypass(int sessionId) async =>
      (await session(sessionId)).bypassAcknowledged.value = true;

  /// Answers permission request [requestId] of chat [sessionId] (control
  /// lane). Returns `false` for an unknown, finished or foreign request.
  bool resolvePermission(int sessionId, String requestId, String optionId) =>
      permissions.resolve(requestId, PermissionSelected(optionId), sessionId: sessionId);

  // --- Login --------------------------------------------------------------------------

  /// Runs [methodId] for [agentId]; after success the agent restarts and the
  /// chats waiting for a login continue.
  Future<AgentLogin> login(String agentId, String methodId) async {
    _checkNotDisposed();
    final slot = _slots[agentId]!;
    final login = auth.login(slot.definition, methodId);
    // Repeated calls return the running login; restart only once for it.
    if (_restartAfter.add(login)) {
      unawaited(
        login.succeeded
            .then((ok) async {
              if (!ok || _disposing) return;
              // The adapter caches its auth state; a new process picks up the login.
              await _closeConnection(slot, reason: 'Agent restarted after login');
              for (final live in await liveSessions) {
                if (live.agentId != agentId || live.status.value != SessionStatus.needsAuth)
                  continue;
                live.problem.value = null;
                if (live.interrupted == SessionOperation.prompt) {
                  live.canRetryPrompt.value = true;
                  _move(live, SessionStatus.cold);
                } else {
                  unawaited(_setupLane(live, () => _ensureReady(live)).catchError((Object _) {}));
                }
              }
            })
            .catchError((Object error, StackTrace stackTrace) {
              l.w('AgentHub | restart after login failed: $error', stackTrace);
            })
            .whenComplete(() => _restartAfter.remove(login)),
      );
    }
    return login;
  }

  // --- Setup ----------------------------------------------------------------------------

  Future<void> _setupLane(LiveSession live, Future<void> Function() operation) {
    final previous = _setupLanes[live.id] ?? Future<void>.value();
    final next = previous.catchError((Object _) {}).then((_) => operation());
    _setupLanes[live.id] = next.catchError((Object _) {});
    return next;
  }

  Future<void> _ensureReady(LiveSession live) async {
    if (live.status.value == SessionStatus.idle) return;
    final connection = await _start(live);
    if (live.acpSessionId == null) {
      await _create(live, connection);
    } else {
      await _load(live, connection);
    }
  }

  Future<AgentConnection> _start(LiveSession live) async {
    _move(live, SessionStatus.starting);
    live.problem.value = null;
    try {
      return await _connect(_slots[live.agentId]!);
    } on Object catch (error) {
      final problem = switch (error) {
        AgentPreflightException(:final message, :final hint) => SessionProblem(
          SessionProblemKind.preflight,
          message,
          hint: hint,
        ),
        AgentStartException(:final message, :final stderrTail) => SessionProblem(
          SessionProblemKind.start,
          message,
          details: stderrTail,
        ),
        _ => SessionProblem(SessionProblemKind.start, '$error'),
      };
      live.interrupted = SessionOperation.start;
      await _fail(live, problem);
      rethrow;
    }
  }

  Future<AgentConnection> _connect(_AgentSlot slot) async {
    final connection = slot.connection;
    if (connection != null) {
      if (connection.isAlive) return connection;
      // A failed turn can surface before the process exit is handled; retire
      // the dead generation first so its chats do not keep stale bindings.
      await _onExit(slot, slot.generation, null);
    }
    return slot.starting ??= () async {
      final generation = ++slot.generation;
      try {
        final started = await _connector(
          slot.definition,
          (context) => _onPermission(slot, generation, context),
        );
        if (_disposing) {
          await started.close();
          throw StateError('AgentHub is disposed');
        }
        slot.connection = started;
        started.incoming.listen((message) {
          if (slot.generation == generation) _route(slot, message);
        });
        unawaited(started.exitCode.then((code) => _onExit(slot, generation, code)));
        return started;
      } finally {
        slot.starting = null;
      }
    }();
  }

  Future<void> _create(
    LiveSession live,
    AgentConnection connection, {
    String? contextLostFrom,
  }) async {
    _move(live, SessionStatus.creating);
    try {
      final response = await connection.agent
          .createSession(NewSessionRequest(cwd: live.cwd, mcpServers: const <McpServer>[]))
          .timeout(setupTimeout);
      final acpId = response.sessionId.value;
      await _database.transaction(() async {
        await (_database.update(_database.sessionsTable)..where((s) => s.id.equals(live.id))).write(
          SessionsTableCompanion(
            acpSessionId: Value<String?>(acpId),
            updatedAt: Value<DateTime>(DateTime.now()),
          ),
        );
        if (contextLostFrom != null) {
          await live.store.addDurable(
            SessionEventOrigin.app,
            SessionEventKind.system,
            <String, Object?>{'type': 'context_lost', 'previousAcpSessionId': contextLostFrom},
          );
        }
      });
      if (contextLostFrom != null) _slots[live.agentId]!.byAcpId.remove(contextLostFrom);
      live
        ..acpSessionId = acpId
        ..configOptions.value = _objects(_plain(response.toJson())['configOptions']);
      // The agent may have stopped meanwhile; the id is kept for the next load.
      if (live.status.value != SessionStatus.creating) return;
      _slots[live.agentId]!.byAcpId[acpId] = live;
      _move(live, SessionStatus.idle);
    } on Object catch (error, stackTrace) {
      await _setupError(live, SessionOperation.create, error, stackTrace);
    }
  }

  Future<void> _load(LiveSession live, AgentConnection connection) async {
    _move(live, SessionStatus.loading);
    final acpId = live.acpSessionId!;
    final slot = _slots[live.agentId]!;
    slot.byAcpId[acpId] = live;
    live.replaying = true;
    try {
      final response = await connection.agent
          .loadSession(
            LoadSessionRequest(
              sessionId: SessionId(acpId),
              cwd: live.cwd,
              mcpServers: const <McpServer>[],
            ),
          )
          .timeout(setupTimeout);
      live.configOptions.value = _objects(_plain(response.toJson())['configOptions']);
      if (live.status.value == SessionStatus.loading) _move(live, SessionStatus.idle);
    } on Object catch (error, stackTrace) {
      slot.byAcpId.remove(acpId);
      await _setupError(live, SessionOperation.load, error, stackTrace);
    } finally {
      live.replaying = false;
    }
  }

  Future<Never> _setupError(
    LiveSession live,
    SessionOperation operation,
    Object error,
    StackTrace stackTrace,
  ) async {
    // Already moved on (the agent stopped, the app closes): just report.
    switch (live.status.value) {
      case SessionStatus.starting || SessionStatus.loading || SessionStatus.creating:
        break;
      default:
        Error.throwWithStackTrace(error, stackTrace);
    }
    live.interrupted = operation;
    if (error case JsonRpcRequestException(:final error) when error.code == kAcpAuthRequiredCode) {
      live.problem.value = SessionProblem(SessionProblemKind.auth, error.message);
      _move(live, SessionStatus.needsAuth);
    } else {
      live.problem.value = switch (error) {
        JsonRpcRequestException(:final error) when error.code == kAcpResourceNotFoundCode =>
          SessionProblem(
            SessionProblemKind.notFound,
            'The agent no longer has this session: ${error.message}',
          ),
        TimeoutException() => SessionProblem(
          SessionProblemKind.transient,
          'The agent did not answer within ${setupTimeout.inSeconds} s',
        ),
        _ => SessionProblem(SessionProblemKind.transient, '$error'),
      };
      _move(live, SessionStatus.setupFailed);
    }
    Error.throwWithStackTrace(error, stackTrace);
  }

  // --- Incoming ---------------------------------------------------------------------------

  void _route(_AgentSlot slot, RawAcpMessage message) {
    if (message.isRequest) {
      slot.rawRequests['${message.id}'] = message;
      return;
    }
    final acpId = message.sessionId;
    if (!message.isNotification || acpId == null) return;
    final live = slot.byAcpId[acpId];
    if (live == null || _isTerminal(live)) return;
    final update = _object(message.params?['update']);
    final kind = message.method == 'session/update'
        ? '${update?['sessionUpdate']}'
        : message.method!;
    // State updates apply even while load replays history.
    switch (kind) {
      case 'available_commands_update':
        // State, not history: ~38 KB per update with the user's whole command list.
        live.availableCommands.value = _objects(update?['availableCommands']);
        return;
      case 'config_option_update':
        live.configOptions.value = _objects(update?['configOptions']);
    }
    if (live.replaying || live.store.isClosed) return;
    live.store.addAgentFrame(kind, message.json);
  }

  Future<RequestPermissionResponse> _onPermission(
    _AgentSlot slot,
    int generation,
    AcpClientRequestContext<RequestPermissionRequest> context,
  ) async {
    final wireId = '${context.requestId.toJson()}';
    // A new process restarts its JSON-RPC ids: qualify them so a stale card
    // can never answer a request of another generation.
    final requestId = '${slot.definition.id}#$generation#$wireId';
    final raw = slot.rawRequests.remove(wireId);
    final live = slot.byAcpId[context.params.sessionId.value];
    if (live == null || _isTerminal(live))
      return _response(const PermissionCancelled('unknown session'));
    final decided = permissions.wait(requestId, sessionId: live.id);
    try {
      await live.store.addDurable(
        SessionEventOrigin.agent,
        SessionEventKind.permissionRequest,
        <String, Object?>{
          'requestId': requestId,
          'params': raw?.params ?? _plain(context.params.toJson()),
        },
      );
    } on Object catch (error) {
      // Fail closed: the agent must not wait forever on a request the user
      // cannot see.
      permissions.resolve(requestId, const PermissionCancelled('could not be saved'));
      _notice(live, 'A permission request could not be saved and was declined: $error');
      // Controlled error: stop the turn instead of letting it go on unseen.
      final acpId = live.acpSessionId;
      if (acpId != null && slot.connection?.isAlive == true) {
        unawaited(
          slot.connection!.agent
              .cancelSession(CancelNotification(sessionId: SessionId(acpId)))
              .catchError((Object _) {}),
        );
      }
      await _failOnce(
        live,
        SessionProblem(
          SessionProblemKind.transient,
          'A permission request could not be saved: $error',
        ),
      );
      return _response(await decided);
    }
    if (live.status.value == SessionStatus.running) _move(live, SessionStatus.awaitingPermission);
    unawaited(
      context.cancellationToken.whenCancelled.then(
        (_) => permissions.resolve(requestId, const PermissionCancelled('withdrawn by the agent')),
      ),
    );
    final decision = await decided;
    await live.store
        .addDurable(
          SessionEventOrigin.user,
          SessionEventKind.permissionResolution,
          <String, Object?>{
            'requestId': requestId,
            ...switch (decision) {
              PermissionSelected(:final optionId) => <String, Object?>{
                'outcome': 'selected',
                'optionId': optionId,
              },
              PermissionCancelled(:final reason) => <String, Object?>{
                'outcome': 'cancelled',
                'reason': reason,
              },
            },
          },
        )
        .then<void>(
          (_) {},
          onError: (Object error) =>
              _notice(live, 'A permission decision could not be saved: $error'),
        );
    if (live.status.value == SessionStatus.awaitingPermission &&
        permissions.pendingFor(live.id).isEmpty) {
      _move(live, SessionStatus.running);
    }
    return _response(decision);
  }

  static RequestPermissionResponse _response(PermissionDecision decision) =>
      RequestPermissionResponse(
        outcome: switch (decision) {
          PermissionSelected(:final optionId) => RequestPermissionOutcomeSelected(
            SelectedPermissionOutcome(optionId: PermissionOptionId(optionId)),
          ),
          PermissionCancelled() => const RequestPermissionOutcomeCancelled(),
        },
      );

  // --- Process lifecycle ------------------------------------------------------------------

  /// Retires generation [generation] of [slot]: called when its process
  /// exits, or earlier by [_connect] when it finds the connection dead.
  /// Idempotent — a second call for the same generation finds nothing to do.
  Future<void> _onExit(_AgentSlot slot, int generation, int? code) async {
    if (slot.generation != generation) return;
    final connection = slot.connection;
    final stderrTail = connection?.stderrTail ?? const <String>[];
    slot.connection = null;
    // The process exited, but the native agent and its MCP servers in the same
    // group may survive it (and hold the pipes open): stop the whole group.
    unawaited(connection?.close().catchError((Object _) {}));
    final sessions = List<LiveSession>.of(slot.byAcpId.values);
    slot
      ..byAcpId.clear()
      ..rawRequests.clear();
    for (final live in sessions) {
      permissions.cancelSession(live.id, 'agent stopped');
      await live.store.flush().catchError((Object _) {});
      // `starting` means the chat is already starting the next generation.
      if (_isTerminal(live) || live.status.value == SessionStatus.starting) continue;
      if (live.status.value.isBusy || live.status.value == SessionStatus.needsAuth) {
        await _failOnce(
          live,
          SessionProblem(
            SessionProblemKind.crash,
            code == null
                ? '${slot.definition.displayName} stopped'
                : '${slot.definition.displayName} stopped (exit code $code)',
            details: stderrTail,
          ),
        );
      } else if (live.status.value == SessionStatus.idle) {
        _move(live, SessionStatus.cold);
      }
    }
  }

  /// Closes [slot]'s connection on purpose. Chats are detached synchronously
  /// (no prompt can reach the dying process): busy ones go to `error` with
  /// [reason], idle ones to `cold`; chats waiting for a login keep waiting.
  Future<void> _closeConnection(_AgentSlot slot, {required String reason}) async {
    final connection = slot.connection;
    if (connection == null) return;
    slot
      ..connection = null
      // Its exit is no longer ours to handle.
      ..generation += 1;
    final sessions = List<LiveSession>.of(slot.byAcpId.values);
    slot
      ..byAcpId.clear()
      ..rawRequests.clear();
    for (final live in sessions) {
      permissions.cancelSession(live.id, reason);
    }
    for (final live in sessions) {
      final status = live.status.value;
      if (_isTerminal(live) || status == SessionStatus.needsAuth) continue;
      if (status.isBusy) {
        await _failOnce(live, SessionProblem(SessionProblemKind.crash, reason));
      } else if (status == SessionStatus.idle) {
        _move(live, SessionStatus.cold);
      }
    }
    await connection.close();
    for (final live in sessions) {
      await live.store.flush().catchError((Object _) {});
    }
  }

  /// Stops every turn and agent: cancel → wait ≤ [turnGrace] for turns to end
  /// → stop the process groups. Always call it when the app exits.
  Future<void> dispose({Duration turnGrace = const Duration(seconds: 3)}) async {
    if (_disposing) return;
    // From here on no new chat, prompt, login or agent start is accepted.
    _disposing = true;
    final sessions = await liveSessions;
    for (final live in sessions) {
      if (live.status.value == SessionStatus.running ||
          live.status.value == SessionStatus.awaitingPermission) {
        await cancel(live.id).catchError((Object _) {});
      }
    }
    await Future.wait<void>(<Future<void>>[
      for (final live in sessions)
        if (live.turn case final Future<void> turn) turn,
    ]).timeout(turnGrace, onTimeout: () => <void>[]);
    permissions.cancelAll('app closed');
    for (final slot in _slots.values) {
      final connection = slot.connection;
      slot
        ..connection = null
        ..generation += 1;
      await connection?.close();
    }
    await auth.dispose();
    for (final live in sessions) {
      live
        ..cancelTimer?.cancel()
        ..status.value = SessionStatus.disposed;
      await live.store.close();
      live.dispose();
    }
    await _notices.close();
  }

  // --- Helpers ----------------------------------------------------------------------------

  void _move(LiveSession live, SessionStatus next) {
    final current = live.status.value;
    if (current == next) return;
    if (!current.canMoveTo(next)) {
      final error = StateError('Session ${live.id}: ${current.name} → ${next.name} is not allowed');
      assert(false, error.message);
      unawaited(
        live.store
            .addDurable(SessionEventOrigin.app, SessionEventKind.system, <String, Object?>{
              'type': 'invalid_transition',
              'from': current.name,
              'to': next.name,
            })
            .then<void>((_) {}, onError: (Object _) {}),
      );
      throw error;
    }
    live.status.value = next;
  }

  Future<void> _fail(LiveSession live, SessionProblem problem) async {
    live.problem.value = problem;
    if (!_isTerminal(live)) _move(live, SessionStatus.error);
    await live.store
        .addDurable(SessionEventOrigin.app, SessionEventKind.system, <String, Object?>{
          'type': 'error',
          'kind': problem.kind.name,
          'message': problem.message,
        })
        .then<void>((_) {}, onError: (Object error) => _notice(live, problem.message));
  }

  /// [_fail] unless the session already failed or is shut down (one error
  /// event per failure, even when the exit handler got there first).
  Future<void> _failOnce(LiveSession live, SessionProblem problem) async {
    if (_isTerminal(live) || live.status.value == SessionStatus.error) return;
    await _fail(live, problem);
  }

  Future<void> _touchSession(LiveSession live, {required String title}) =>
      _database.transaction(() async {
        final record = await (_database.select(
          _database.sessionsTable,
        )..where((s) => s.id.equals(live.id))).getSingle();
        await (_database.update(_database.sessionsTable)..where((s) => s.id.equals(live.id))).write(
          SessionsTableCompanion(
            updatedAt: Value<DateTime>(DateTime.now()),
            title: record.title.isEmpty
                ? Value<String>(title.length > 60 ? title.substring(0, 60) : title)
                : const Value<String>.absent(),
          ),
        );
      });

  void _notice(LiveSession live, String message) {
    l.w('AgentHub | session ${live.id}: $message');
    if (!_notices.isClosed) _notices.add(HubNotice(live.id, message));
  }

  bool _isTerminal(LiveSession live) => live.status.value == SessionStatus.disposed;

  void _checkNotDisposed() {
    if (_disposing) throw StateError('AgentHub is disposed');
  }

  static Map<String, Object?> _plain(Object? json) =>
      (jsonDecode(jsonEncode(json)) as Map<Object?, Object?>).cast<String, Object?>();

  static Map<String, Object?>? _object(Object? value) => switch (value) {
    final Map<Object?, Object?> map => map.cast<String, Object?>(),
    _ => null,
  };

  static List<Map<String, Object?>> _objects(Object? value) => switch (value) {
    final List<Object?> list => <Map<String, Object?>>[
      for (final item in list)
        if (item is Map<Object?, Object?>) item.cast<String, Object?>(),
    ],
    _ => const <Map<String, Object?>>[],
  };
}
