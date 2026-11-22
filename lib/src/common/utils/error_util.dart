// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/telemetry/telemetry.dart';

/// The one place app code reports an error.
///
/// A thin facade over [ErrorHub]: [logError] writes the error to the log and, unless it is
/// expected, queues it for crash reports. A failure of `ErrorUtil` itself is never thrown and does
/// not call `ErrorUtil` again, it goes to the console. Before [configure] errors go to the console
/// and pile up in memory.
abstract final class ErrorUtil {
  /// The app-wide hub; `startTelemetry` connects the log to it.
  static final ErrorHub hub = ErrorHub();

  /// Where failures of `ErrorUtil` itself and errors before [configure] are written.
  @visibleForTesting
  static void Function(String text) get console => hub.console;

  /// Replaces [console] (tests).
  @visibleForTesting
  static set console(void Function(String text) value) => hub.console = value;

  /// Connects the log and the queue.
  static void configure(TelemetryRuntime runtime) => hub.configure(runtime);

  /// Disconnects the log of [runtime] before its database closes: later errors pile up in memory
  /// until the next [configure].
  static void disconnect(TelemetryRuntime runtime) => hub.disconnect(runtime);

  /// Waits until every started call is written: before the log database closes.
  static Future<void> settled() => hub.settled();

  /// Disconnects the log and the queue (tests).
  @visibleForTesting
  static void reset() => hub.reset();

  /// Reports [error]. [hint] says briefly where it happened.
  static Future<void> logError(
    Object error,
    StackTrace stackTrace, {
    String? hint,
    bool fatal = false,
  }) => hub.logError(error, stackTrace, hint: hint, fatal: fatal);

  /// Reports an event without an exception: a failure that was not thrown.
  static Future<void> logMessage(
    String message, {
    StackTrace? stackTrace,
    String? hint,
    bool warning = false,
  }) => hub.logMessage(message, stackTrace: stackTrace, hint: hint, warning: warning);

  /// Rethrows the error with the stack trace.
  static Never throwWithStackTrace(Object error, StackTrace stackTrace) =>
      Error.throwWithStackTrace(error, stackTrace);
}
