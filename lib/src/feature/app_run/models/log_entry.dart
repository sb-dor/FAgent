import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';

/// How serious a [LogEntry] is.
enum LogLevel { info, warning, error }

/// One line of the running app's output.
@immutable
final class LogEntry {
  /// Creates a log line.
  const LogEntry({
    required this.seq,
    required this.time,
    required this.level,
    required this.text,
    this.error,
    this.sentToAgent = false,
  });

  /// The position of the line in its project's output, counting from 0.
  final int seq;

  /// When the app printed the line.
  final DateTime time;

  /// The severity.
  final LogLevel level;

  /// The line itself.
  final String text;

  /// The structured error behind the line, if there is one.
  final RunError? error;

  /// Whether the user already sent this line to the agent.
  final bool sentToAgent;

  /// A copy with the given fields replaced.
  LogEntry copyWith({bool? sentToAgent}) => LogEntry(
    seq: seq,
    time: time,
    level: level,
    text: text,
    error: error,
    sentToAgent: sentToAgent ?? this.sentToAgent,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LogEntry &&
          other.seq == seq &&
          other.time == time &&
          other.level == level &&
          other.text == text &&
          other.error == error &&
          other.sentToAgent == sentToAgent;

  @override
  int get hashCode => Object.hash(seq, time, level, text, error, sentToAgent);

  @override
  String toString() => 'LogEntry($seq, ${level.name}, $text)';
}
