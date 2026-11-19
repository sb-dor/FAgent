import 'package:meta/meta.dart';

/// Why a session is not usable right now.
enum SessionProblemKind {
  /// The machine cannot run the agent (Node.js or the executable is missing).
  preflight,

  /// The agent process did not start or initialize.
  start,

  /// `session/load` says the agent session does not exist (-32002).
  notFound,

  /// A request failed or timed out; retrying may help.
  transient,

  /// The agent needs a login.
  auth,

  /// The agent process stopped.
  crash,

  /// The turn does not end after Stop.
  stuck,

  /// The chat's agent is no longer configured; nothing can be retried.
  removed,
}

/// {@template session_problem}
/// What the UI shows for `setupFailed`, `needsAuth`, `error` and a stuck stop.
/// {@endtemplate}
@immutable
final class SessionProblem {
  /// {@macro session_problem}
  const SessionProblem(this.kind, this.message, {this.hint, this.details = const <String>[]});

  /// Category, decides which actions the UI offers.
  final SessionProblemKind kind;

  /// Human-readable cause.
  final String message;

  /// How to fix it, when known.
  final String? hint;

  /// Diagnostic lines (agent stderr tail).
  final List<String> details;

  @override
  String toString() => 'SessionProblem(${kind.name}: $message)';
}
