import 'dart:async';

import 'package:meta/meta.dart';

/// How a permission request ended.
@immutable
sealed class PermissionDecision {
  const PermissionDecision();
}

/// The user picked one of the options the agent offered.
final class PermissionSelected extends PermissionDecision {
  /// Creates a selected decision.
  const PermissionSelected(this.optionId);

  /// `optionId` from the request.
  final String optionId;

  @override
  String toString() => 'PermissionSelected($optionId)';
}

/// The turn was cancelled, the app stopped, or the request could not be saved.
final class PermissionCancelled extends PermissionDecision {
  /// Creates a cancelled decision.
  const PermissionCancelled(this.reason);

  /// Why the request was cancelled.
  final String reason;

  @override
  String toString() => 'PermissionCancelled($reason)';
}

/// {@template permission_broker}
/// Pending `session/request_permission` requests, keyed by their JSON-RPC id.
///
/// Every request completes exactly once: the first decision wins, later ones
/// (a late click after cancel, a second click) are ignored.
/// {@endtemplate}
final class PermissionBroker {
  final Map<String, ({int sessionId, Completer<PermissionDecision> completer})> _pending =
      <String, ({int sessionId, Completer<PermissionDecision> completer})>{};

  /// Registers request [requestId] of app session [sessionId] and waits for its
  /// decision.
  Future<PermissionDecision> wait(String requestId, {required int sessionId}) {
    if (_pending.containsKey(requestId)) {
      throw StateError('Permission request $requestId is already pending');
    }
    final completer = Completer<PermissionDecision>();
    _pending[requestId] = (sessionId: sessionId, completer: completer);
    return completer.future;
  }

  /// Resolves [requestId]. Returns `false` when it is unknown, already done,
  /// or (with [sessionId]) belongs to another session.
  bool resolve(String requestId, PermissionDecision decision, {int? sessionId}) {
    final pending = _pending[requestId];
    if (pending == null || (sessionId != null && pending.sessionId != sessionId)) return false;
    _pending.remove(requestId);
    pending.completer.complete(decision);
    return true;
  }

  /// Ids of the requests app session [sessionId] waits on.
  List<String> pendingFor(int sessionId) => <String>[
    for (final MapEntry(:key, :value) in _pending.entries)
      if (value.sessionId == sessionId) key,
  ];

  /// Cancels every pending request of app session [sessionId].
  void cancelSession(int sessionId, String reason) {
    for (final id in pendingFor(sessionId)) {
      resolve(id, PermissionCancelled(reason));
    }
  }

  /// Cancels every pending request.
  void cancelAll(String reason) {
    for (final id in List<String>.of(_pending.keys)) {
      resolve(id, PermissionCancelled(reason));
    }
  }
}
