import 'dart:async';

import 'package:dart_acp_sdk/dart_acp_sdk.dart' hide Error;
import 'package:flutter_code_agent/src/common/acp/agent_connection.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub_types.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/raw_acp_message.dart';
import 'package:l/l.dart';

/// Answers a permission request of generation `generation` of [slot]'s process.
typedef AgentSlotPermissionHandler = Future<RequestPermissionResponse> Function(
  AgentSlot slot,
  int generation,
  AcpClientRequestContext<RequestPermissionRequest> context,
);

/// One configured agent: its definition, its connection (if started) and the
/// chats bound to the connection's current generation.
final class AgentSlot {
  /// Creates the slot of agent [id].
  AgentSlot(this.id, this.definition);

  /// The key chats use (`sessions.agentId`).
  final String id;

  /// Replaced when the user edits the agent; the next start uses it.
  AgentDefinition definition;

  /// The running connection, if any.
  AgentConnection? connection;

  /// The start in flight, if any (starts are single-flight).
  Future<AgentConnection>? starting;

  /// Bumped by every start and every deliberate close: frames and exits of an
  /// older generation are ignored.
  int generation = 0;

  /// The definition changed: restart once no chat of the agent is busy.
  bool restartPending = false;

  /// The agent was removed; nothing starts for it any more.
  bool retired = false;

  /// `authenticate` / `logout` calls in flight (they hold off a restart).
  int signIns = 0;

  /// Chats bound to the current connection, by ACP session id.
  final Map<String, LiveSession> byAcpId = <String, LiveSession>{};

  /// Raw JSON-RPC requests of the current connection, by wire id (the
  /// permission handler reads the raw params from them).
  final Map<String, RawAcpMessage> rawRequests = <String, RawAcpMessage>{};
}

/// {@template agent_slot_registry}
/// Owns the [AgentSlot] of every configured agent and their connections.
///
/// * Applies a new definition list ([setAgents]): add, keep, restart when
///   idle, or retire and close.
/// * Starts connections lazily and single-flight ([connect]); each start is a
///   new generation and frames of old generations are dropped.
/// * Closes connections on purpose ([closeConnection]) and tracks the closing
///   work nobody awaits ([track]) so [dispose] can wait for it.
///
/// Everything that touches chats (statuses, failing busy chats, marking chats
/// removed, the permission broker) belongs to the hub and is reached through
/// the callbacks passed to the constructor.
/// {@endtemplate}
final class AgentSlotRegistry {
  /// {@macro agent_slot_registry}
  AgentSlotRegistry({
    required Map<String, AgentDefinition> agents,
    required this._connector,
    required this._isDisposing,
    required this._isAgentBusy,
    required this._onRemoved,
    required this._onDetached,
    required this._onPermission,
    required this._onFrame,
    required this._onExit,
  }) : _slots = <String, AgentSlot>{
         for (final MapEntry(:key, :value) in agents.entries) key: AgentSlot(key, value),
       };

  final AgentConnector _connector;

  /// Whether the hub is shutting down: nothing starts or restarts any more.
  final bool Function() _isDisposing;

  /// Whether a chat of the agent has a busy status or queued setup work.
  final bool Function(String agentId) _isAgentBusy;

  /// The agent was removed: its chats go to `error` (synchronously).
  final void Function(String agentId) _onRemoved;

  /// A connection was closed on purpose: [sessions] were bound to it.
  final Future<void> Function(List<LiveSession> sessions, String reason) _onDetached;

  final AgentSlotPermissionHandler _onPermission;

  /// A frame of the current generation arrived.
  final void Function(AgentSlot slot, RawAcpMessage message) _onFrame;

  /// The process of generation `generation` exited (or was found dead).
  final Future<void> Function(AgentSlot slot, int generation, int? code) _onExit;

  final Map<String, AgentSlot> _slots;

  /// Work nobody awaits (closing a removed or edited agent, marking the chats
  /// of a removed one); [dispose] waits for it.
  final Set<Future<void>> _closing = <Future<void>>{};

  /// Definitions of the configured agents.
  Iterable<AgentDefinition> get definitions => _slots.values.map((s) => s.definition);

  /// The slot of [agentId], if it is configured.
  AgentSlot? operator [](String agentId) => _slots[agentId];

  /// Whether [agentId] is configured.
  bool contains(String agentId) => _slots.containsKey(agentId);

  /// The slot of [agentId]; a [StateError] for an unknown agent.
  AgentSlot slotOf(String agentId) =>
      _slots[agentId] ?? (throw StateError('Unknown agent $agentId'));

  /// Replaces the agents (see `AgentHub.setAgents`).
  void setAgents(List<AgentDefinition> definitions) {
    if (_isDisposing()) return;
    final next = <String, AgentDefinition>{
      for (final definition in definitions) definition.id: definition,
    };
    for (final id in List<String>.of(_slots.keys)) {
      if (next.containsKey(id)) continue;
      final slot = _slots.remove(id)!..retired = true;
      _onRemoved(id);
      track(closeConnection(slot, reason: 'Agent removed'));
    }
    for (final definition in next.values) {
      final slot = _slots[definition.id];
      if (slot == null) {
        _slots[definition.id] = AgentSlot(definition.id, definition);
      } else if (slot.definition != definition) {
        slot
          ..definition = definition
          ..restartPending = true;
        _restartIfIdle(slot);
      }
    }
  }

  /// The live connection of [slot], starting it if needed (single-flight).
  Future<AgentConnection> connect(AgentSlot slot) async {
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
        if (_isDisposing() || slot.retired) {
          await started.close();
          if (_isDisposing()) throw StateError('AgentHub is disposed');
          throw const AgentRemovedException();
        }
        slot.connection = started;
        started.incoming.listen((message) {
          if (slot.generation == generation) _onFrame(slot, message);
        });
        unawaited(started.exitCode.then((code) => _onExit(slot, generation, code)));
        return started;
      } finally {
        slot.starting = null;
      }
    }();
  }

  /// Closes [slot]'s connection on purpose. Chats are detached synchronously
  /// (no prompt can reach the dying process) and handed to the hub with
  /// [reason]; their journals are flushed once the process is closed.
  Future<void> closeConnection(AgentSlot slot, {required String reason}) async {
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
    await _onDetached(sessions, reason);
    await connection.close();
    for (final live in sessions) {
      await live.store.flush().catchError((Object _) {});
    }
  }

  /// Checks, after the current step, whether an edited agent can restart now.
  void scheduleRestartCheck(String agentId) {
    final slot = _slots[agentId];
    if (slot == null || !slot.restartPending) return;
    scheduleMicrotask(() => _restartIfIdle(slot));
  }

  /// Closes an edited agent's connection once nothing of it is busy: no chat
  /// with a busy status or queued setup work, no sign-in call in flight.
  void _restartIfIdle(AgentSlot slot) {
    if (!slot.restartPending || slot.retired || _isDisposing()) return;
    if (slot.signIns > 0) return;
    if (_isAgentBusy(slot.id)) return;
    slot.restartPending = false;
    track(closeConnection(slot, reason: 'Agent settings changed'));
  }

  /// Runs [work] without awaiting it; errors are logged and [dispose] waits
  /// for it.
  void track(Future<void> work) {
    final tracked = work.catchError((Object error, StackTrace stackTrace) {
      l.w('AgentHub | updating an agent failed: $error', stackTrace);
    });
    _closing.add(tracked);
    unawaited(tracked.whenComplete(() => _closing.remove(tracked)));
  }

  /// Waits for the [track]ed work, then stops every connection (their exits
  /// are no longer handled).
  Future<void> dispose() async {
    await Future.wait<void>(List<Future<void>>.of(_closing));
    for (final slot in _slots.values) {
      final connection = slot.connection;
      slot
        ..connection = null
        ..generation += 1;
      await connection?.close();
    }
  }
}
