// The class groups the reporting calls under one name at every call site (`ErrorUtil.logError`).
// ignore_for_file: avoid_classes_with_only_static_members

import 'package:{{package}}/_core/telemetry/telemetry_setup.dart';

/// The one place app code reports an error (docs/rules/controllers.md, "Reporting an error").
///
/// A thin facade over the error log (`telemetry_setup.dart`): [logError] writes the error to the
/// log and, unless `isExpectedFailure` says it is expected, queues it for the crash reporter. It
/// never throws: a failure of the log goes to the console. Before the "Error log" startup step
/// errors go to the console and wait in memory. On the web there is no log: the console only.
abstract final class ErrorUtil {
  /// Reports [error]. [hint] says briefly where it happened.
  static Future<void> logError(
    Object error,
    StackTrace stackTrace, {
    String? hint,
    bool fatal = false,
  }) => reportError(error, stackTrace, hint: hint, fatal: fatal);

  /// Reports an event without an exception: a failure that was not thrown.
  static Future<void> logMessage(
    String message, {
    StackTrace? stackTrace,
    String? hint,
    bool warning = false,
  }) => reportMessage(message, stackTrace: stackTrace, hint: hint, warning: warning);

  /// Waits until every started call is written: before the log closes.
  static Future<void> settled() => reportsSettled();

  /// Rethrows the error with the stack trace.
  static Never throwWithStackTrace(Object error, StackTrace stackTrace) =>
      Error.throwWithStackTrace(error, stackTrace);
}
