import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error_kind.dart';

/// A problem the running app reported: a framework exception, a build failure.
@immutable
final class RunError {
  /// Creates an error.
  const RunError({
    required this.kind,
    required this.title,
    required this.message,
    this.location,
    this.file,
    this.line,
    this.stack,
  });

  /// How many stack lines [forAgent] keeps.
  static const int agentStackLines = 20;

  /// What the error is; the UI shows its title in the user's language by it.
  final RunErrorKind kind;

  /// A short name in English, for example `Layout overflow`; the agent gets it as it is.
  final String title;

  /// What went wrong, as the app printed it.
  final String message;

  /// Where to look, for example `booking_card.dart:42:12`.
  final String? location;

  /// The project-relative path of the file at fault.
  final String? file;

  /// The line in [file].
  final int? line;

  /// The stack trace, one frame per line.
  final String? stack;

  /// Where to look, as one short text: the [location] the app printed, else `file:line`, else the
  /// [file] alone; `null` when the error names no place.
  String? get place => location ?? (file == null ? null : (line == null ? file : '$file:$line'));

  /// The error as text for the agent: the title, the message, the place and the first
  /// [agentStackLines] lines of the stack in a code block.
  String forAgent() {
    final place = this.place;
    final stackLines = (stack ?? '').split('\n').where((line) => line.trim().isNotEmpty);
    final excerpt = stackLines.take(agentStackLines).join('\n');
    return <String>[
      title,
      message,
      if (place != null) 'Location: $place',
      if (excerpt.isNotEmpty) '```\n$excerpt\n```',
    ].join('\n');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RunError &&
          other.kind == kind &&
          other.title == title &&
          other.message == message &&
          other.location == location &&
          other.file == file &&
          other.line == line &&
          other.stack == stack;

  @override
  int get hashCode => Object.hash(kind, title, message, location, file, line, stack);

  @override
  String toString() => 'RunError($title, $location)';
}
