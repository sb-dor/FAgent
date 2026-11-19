import 'package:flutter_code_agent/src/common/utils/expected_exception.dart';

/// The agent process ended while it started, before it finished initializing.
final class AgentExitedException extends ExpectedException {
  /// Creates the exception for a process that ended with [exitCode].
  const AgentExitedException(this.exitCode);

  /// The exit code of the agent process.
  final int exitCode;

  /// A plain sentence: the start message of the agent includes it.
  @override
  String toString() => 'The agent exited with code $exitCode.';
}

/// The agent stopped while a chat was being prepared for its message.
final class AgentStoppedException extends ExpectedException {
  /// Creates the exception.
  const AgentStoppedException();

  @override
  String toString() =>
      'AgentStoppedException: the agent stopped while the session was being prepared';
}
