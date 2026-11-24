/// Lifecycle of one chat's agent session (`docs/M1_PLAN.md`, state table).
enum SessionStatus {
  /// No agent session in the current process yet.
  cold,

  /// The agent process is starting.
  starting,

  /// `session/load` restores the agent's context.
  loading,

  /// `session/new` creates the agent session.
  creating,

  /// Ready for a prompt.
  idle,

  /// A turn is running.
  running,

  /// The agent waits for the user's permission decision.
  awaitingPermission,

  /// Stop was requested; waiting for the turn to end.
  cancelling,

  /// Start, load or new failed; the user can retry.
  setupFailed,

  /// The agent needs the user to log in.
  needsAuth,

  /// The agent process stopped or a request failed unexpectedly.
  error,

  /// The app is shutting down.
  disposed;

  /// A turn or setup is in flight: closing the app interrupts it.
  bool get isBusy => switch (this) {
    starting || loading || creating || running || awaitingPermission || cancelling => true,
    _ => false,
  };

  static const Map<SessionStatus, Set<SessionStatus>> _allowed =
      <SessionStatus, Set<SessionStatus>>{
        cold: <SessionStatus>{starting},
        starting: <SessionStatus>{loading, creating, needsAuth},
        loading: <SessionStatus>{idle, setupFailed, needsAuth},
        creating: <SessionStatus>{idle, setupFailed, needsAuth},
        idle: <SessionStatus>{running, cold},
        running: <SessionStatus>{awaitingPermission, cancelling, idle, needsAuth},
        // `idle`: the turn ended while a request was still open.
        awaitingPermission: <SessionStatus>{running, cancelling, idle},
        cancelling: <SessionStatus>{idle},
        setupFailed: <SessionStatus>{starting, loading, creating},
        needsAuth: <SessionStatus>{starting, loading, creating, idle, cold},
        error: <SessionStatus>{starting, cold},
        disposed: <SessionStatus>{},
      };

  /// Whether the state table allows moving from this status to [next].
  ///
  /// `error` and `disposed` are reachable from any status except `disposed`.
  bool canMoveTo(SessionStatus next) {
    if (this == disposed) return false;
    if (next == error || next == disposed) return true;
    return _allowed[this]!.contains(next);
  }
}
