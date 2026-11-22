import 'dart:async';
import 'dart:io';

import 'package:flutter_code_agent/src/common/telemetry/error_outbox.dart';
import 'package:flutter_code_agent/src/common/telemetry/log_buffer.dart';
import 'package:flutter_code_agent/src/common/telemetry/redact.dart';
import 'package:l/l.dart';

/// The message that [ErrorReporter.logMessage] puts into the queue instead of an exception.
final class LoggedMessage {
  /// Creates a message.
  const LoggedMessage(this.text);

  /// The text.
  final String text;

  @override
  String toString() => text;
}

/// The shared core of `ErrorUtil`: writes to the `l` log and, if the error is not expected, to
/// the send queue with the last 100 log lines.
///
/// A failure of the core is never thrown and never calls the core again: it goes to [console]. A
/// call from the core itself (a log failure reporting itself) is skipped: the zone marks only the
/// work of that call, neighbouring calls do not suffer.
final class ErrorReporter {
  /// Creates the core. [isExpected] decides that an error is expected and stays out of the queue.
  ErrorReporter({
    required this.outbox,
    required this.buffer,
    required this.isExpected,
    void Function(String text)? console,
  }) : console = console ?? _stderr;

  /// How many of the last log lines are attached to an error.
  static const int breadcrumbCount = 100;

  static const Symbol _inside = #telemetry.errorReporter.inside;

  /// The queue of errors to send.
  final ErrorOutbox outbox;

  /// The last log lines in memory.
  final LogBuffer buffer;

  /// Whether the error is expected.
  bool Function(Object error) isExpected;

  /// Where failures of the core itself are written; `stderr` by default.
  void Function(String text) console;

  final Set<Future<void>> _inflight = {};

  /// Waits until all started calls are written: before the log database is closed.
  Future<void> settled() async {
    while (_inflight.isNotEmpty) {
      await Future.wait(_inflight.toList());
    }
  }

  /// Reports the error [error]. [hint] says briefly where it happened.
  ///
  /// [at] and [breadcrumbs] are needed when the record was postponed until the log was connected:
  /// then the queue gets the time and the log lines of the moment of the error.
  Future<void> logError(
    Object error,
    StackTrace stackTrace, {
    String? hint,
    bool fatal = false,
    DateTime? at,
    List<String>? breadcrumbs,
  }) => _guard(() async {
    final text = redactSecrets(hint == null ? '$error' : '$hint: $error');
    l.e(text, stackTrace);
    if (isExpected(error)) {
      return;
    }
    // Only the queue needs the log lines: an expected error does not count them.
    final crumbs = breadcrumbs ?? buffer.lastLines(breadcrumbCount);
    await outbox.add(
      error: error,
      stack: stackTrace,
      hint: hint,
      level: fatal ? 'fatal' : 'error',
      breadcrumbs: crumbs,
      at: at,
    );
  });

  /// Reports an event without an exception: a failure that was not thrown.
  Future<void> logMessage(
    String message, {
    StackTrace? stackTrace,
    String? hint,
    bool warning = false,
    DateTime? at,
    List<String>? breadcrumbs,
  }) => _guard(() async {
    final text = redactSecrets(hint == null ? message : '$hint: $message');
    final stack = stackTrace ?? StackTrace.current;
    final crumbs = breadcrumbs ?? buffer.lastLines(breadcrumbCount);
    if (warning) {
      l.w(text, stack);
    } else {
      l.e(text, stack);
    }
    await outbox.add(
      error: LoggedMessage(message),
      stack: stack,
      hint: hint,
      level: warning ? 'warning' : 'error',
      breadcrumbs: crumbs,
      at: at,
    );
  });

  Future<void> _guard(Future<void> Function() body) async {
    if (Zone.current[_inside] == true) {
      _write('ErrorUtil: repeated call from ErrorUtil skipped');
      return;
    }
    final job = _run(body);
    _inflight.add(job);
    await job.whenComplete(() => _inflight.remove(job));
  }

  Future<void> _run(Future<void> Function() body) async {
    try {
      await runZoned(body, zoneValues: {_inside: true});
    } on Object catch (error) {
      _write('ErrorUtil: the error log failed: $error');
    }
  }

  void _write(String text) {
    try {
      console(text);
    } on Object {
      // The output is unavailable: nothing to lose.
    }
  }
}

void _stderr(String text) => stderr.writeln(text);
