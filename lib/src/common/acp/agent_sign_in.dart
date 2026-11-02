import 'dart:async';

import 'package:dart_acp_sdk/dart_acp_sdk.dart' hide Error;
import 'package:flutter_code_agent/src/common/acp/agent_auth.dart';
import 'package:flutter_code_agent/src/common/acp/agent_slot_registry.dart';
import 'package:l/l.dart';

/// {@template agent_sign_in}
/// Signs agents in and out: terminal logins ([AgentAuth]), ACP
/// `authenticate` and ACP `logout`.
///
/// Connections come from the [AgentSlotRegistry]; while an `authenticate` or
/// `logout` call is in flight the agent's slot counts it
/// ([AgentSlot.signIns]), which holds off a restart. After a successful
/// sign-in the hub continues the agent's chats waiting for a login (the
/// `continueAfterSignIn` callback).
/// {@endtemplate}
final class AgentSignIn {
  /// {@macro agent_sign_in}
  AgentSignIn({
    required this._registry,
    required this._auth,
    required this._isDisposing,
    required this._continueAfterSignIn,
  });

  final AgentSlotRegistry _registry;
  final AgentAuth _auth;

  /// Whether the hub is shutting down: no sign-in starts any more.
  final bool Function() _isDisposing;

  /// Every chat of the agent waiting for a login continues.
  final Future<void> Function(String agentId) _continueAfterSignIn;

  /// Logins whose success restarts the agent (each restarts it only once).
  final Set<AgentLogin> _restartAfter = <AgentLogin>{};

  /// Runs [methodId] for [agentId]; after success the agent restarts and the
  /// chats waiting for a login continue.
  Future<AgentLogin> login(String agentId, String methodId) async {
    _checkNotDisposed();
    final slot = _registry.slotOf(agentId);
    final login = _auth.login(slot.definition, methodId);
    // Repeated calls return the running login; restart only once for it.
    if (_restartAfter.add(login)) {
      unawaited(
        login.succeeded
            .then((ok) async {
              if (!ok || _isDisposing()) return;
              // The adapter caches its auth state; a new process picks up the login.
              await _registry.closeConnection(slot, reason: 'Agent restarted after login');
              await _continueAfterSignIn(agentId);
            })
            .catchError((Object error, StackTrace stackTrace) {
              l.w('AgentHub | restart after login failed: $error', stackTrace);
            })
            .whenComplete(() => _restartAfter.remove(login)),
      );
    }
    return login;
  }

  /// Signs [agentId] in with ACP `authenticate` and method [methodId] (a
  /// browser sign-in, or an API key the agent reads from its environment),
  /// starting the agent if needed. There is no time limit: the agent may wait
  /// for the user in a browser. On success the agent's chats waiting for a
  /// login continue, on the same connection.
  ///
  /// Cancelling [cancel] closes the agent's connection (reason
  /// `Sign-in cancelled`; chats waiting for a login keep waiting) and the call
  /// throws a [CancellationException]. Other errors propagate.
  Future<void> authenticate(String agentId, String methodId, {CancellationToken? cancel}) async {
    _checkNotDisposed();
    final slot = _registry.slotOf(agentId)..signIns += 1;
    try {
      cancel?.throwIfCancelled();
      final connection = await _registry.connect(slot);
      final generation = slot.generation;
      // Runs at once when cancelled during the start.
      final registration = cancel?.register((_) {
        if (slot.generation == generation) {
          _registry.track(_registry.closeConnection(slot, reason: 'Sign-in cancelled'));
        }
      });
      try {
        await connection.agent.authenticate(
          AuthenticateRequest(methodId: AuthMethodId(methodId)),
          cancellationToken: cancel,
        );
      } on Object {
        // The closed connection fails the request with its own error.
        if (cancel != null && cancel.isCancelled) throw CancellationException(cancel.reason);
        rethrow;
      } finally {
        registration?.dispose();
      }
    } finally {
      slot.signIns -= 1;
      _registry.scheduleRestartCheck(agentId);
    }
    if (_isDisposing()) return;
    await _continueAfterSignIn(agentId);
  }

  /// Signs [agentId] out with ACP `logout` (starting the agent if needed),
  /// then closes its connection.
  Future<void> logout(String agentId) async {
    _checkNotDisposed();
    final slot = _registry.slotOf(agentId)..signIns += 1;
    try {
      final connection = await _registry.connect(slot);
      await connection.agent.logout(LogoutRequest());
    } finally {
      slot.signIns -= 1;
      _registry.scheduleRestartCheck(agentId);
    }
    await _registry.closeConnection(slot, reason: 'Signed out');
  }

  void _checkNotDisposed() {
    if (_isDisposing()) throw StateError('AgentHub is disposed');
  }
}
