import 'dart:async';
import 'dart:io';

import 'package:flutter_code_agent/_core/telemetry/log_buffer.dart';
import 'package:flutter_code_agent/_core/telemetry/redact.dart';
import 'package:flutter_code_agent/_core/telemetry/telemetry_runtime.dart';
import 'package:l/l.dart';

typedef _Replay = Future<void> Function(TelemetryRuntime runtime);

/// The entry point of `ErrorUtil`: until the log is connected ([configure]), errors are written
/// to [console] and pile up in memory (up to [pendingLimit]) with the time and the log lines of the
/// moment of the error; on [configure] they go to the queue. A failure of the hub is not thrown.
final class ErrorHub {
  /// Creates the hub; [console] is `stderr` by default.
  ErrorHub({void Function(String text)? console}) : console = console ?? _stderr {
    _watch();
  }

  /// How many errors before [configure] are kept in memory.
  static const int pendingLimit = 100;

  /// Where failures of `ErrorUtil` itself and errors before [configure] are written.
  void Function(String text) console;

  TelemetryRuntime? _runtime;
  final List<_Replay> _pending = [];

  // Its own last log lines for errors that came before the database was connected.
  final LogBuffer _early = LogBuffer();
  StreamSubscription<LogMessage>? _earlyLogs;

  void _watch() {
    _earlyLogs ??= l.listen(_early.add);
  }

  /// Connects the log and the queue and sends the accumulated errors.
  void configure(TelemetryRuntime runtime) {
    _runtime = runtime;
    runtime.reporter.console = _console;
    unawaited(_earlyLogs?.cancel());
    _earlyLogs = null;
    _early.clear();
    final pending = List.of(_pending);
    _pending.clear();
    for (final replay in pending) {
      unawaited(replay(runtime));
    }
  }

  /// Disconnects the log of [runtime] before its database is closed: the next errors pile up in
  /// memory until the next [configure]. A foreign log is not touched.
  void disconnect(TelemetryRuntime runtime) {
    if (identical(_runtime, runtime)) {
      _runtime = null;
      _early.clear();
      _watch();
    }
  }

  /// Waits until all started calls are written: before the log database is closed.
  Future<void> settled() async => await _runtime?.settled();

  /// Disconnects the log and erases the memory of early errors (tests).
  void reset() {
    _runtime = null;
    _pending.clear();
    _early.clear();
    unawaited(_earlyLogs?.cancel());
    _earlyLogs = null;
    console = _stderr;
  }

  /// Reports the error [error]. [hint] says briefly where it happened.
  Future<void> logError(Object error, StackTrace stackTrace, {String? hint, bool fatal = false}) {
    final runtime = _runtime;
    if (runtime != null) {
      return runtime.reporter.logError(error, stackTrace, hint: hint, fatal: fatal);
    }
    _console(redactSecrets('${hint == null ? '' : '$hint: '}$error\n$stackTrace'));
    final at = DateTime.now().toUtc();
    final crumbs = _early.lastLines(100);
    _remember(
      (runtime) => runtime.reporter.logError(
        error,
        stackTrace,
        hint: hint,
        fatal: fatal,
        at: at,
        breadcrumbs: crumbs,
      ),
    );
    return Future<void>.value();
  }

  /// Reports an event without an exception: a failure that was not thrown.
  Future<void> logMessage(
    String message, {
    StackTrace? stackTrace,
    String? hint,
    bool warning = false,
  }) {
    final runtime = _runtime;
    if (runtime != null) {
      return runtime.reporter.logMessage(
        message,
        stackTrace: stackTrace,
        hint: hint,
        warning: warning,
      );
    }
    final stack = stackTrace ?? StackTrace.current;
    _console(redactSecrets('${hint == null ? '' : '$hint: '}$message\n$stack'));
    final at = DateTime.now().toUtc();
    final crumbs = _early.lastLines(100);
    _remember(
      (runtime) => runtime.reporter.logMessage(
        message,
        stackTrace: stack,
        hint: hint,
        warning: warning,
        at: at,
        breadcrumbs: crumbs,
      ),
    );
    return Future<void>.value();
  }

  void _remember(_Replay replay) {
    _pending.add(replay);
    if (_pending.length > pendingLimit) {
      _pending.removeAt(0);
    }
  }

  void _console(String text) {
    try {
      console(text);
    } on Object {
      // The output is unavailable: nothing to lose.
    }
  }
}

void _stderr(String text) => stderr.writeln(text);
