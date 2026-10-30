// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';

import 'package:l/l.dart';

/// Error utils.
abstract final class ErrorUtil {
  /// Log the error to the console.
  ///
  /// Crash reporting (Sentry or similar) plugs in here once the app is released.
  static Future<void> logError(
    Object exception,
    StackTrace stackTrace, {
    String? hint,
    bool fatal = false,
  }) async {
    try {
      if (exception is String) {
        return await logMessage(exception, stackTrace: stackTrace, hint: hint, warning: true);
      }
      l.e(hint == null ? exception : '$hint\n$exception', stackTrace);
    } on Object catch (error, stackTrace) {
      l.e('Error while logging error "$error" inside ErrorUtil.logError', stackTrace);
    }
  }

  /// Logs a message to the console.
  static Future<void> logMessage(
    String message, {
    StackTrace? stackTrace,
    String? hint,
    bool warning = false,
  }) async {
    try {
      final text = hint == null ? message : '$hint\n$message';
      warning ? l.w(text, stackTrace) : l.i(text);
    } on Object catch (error, stackTrace) {
      l.e('Error while logging error "$error" inside ErrorUtil.logMessage', stackTrace);
    }
  }

  /// Rethrows the error with the stack trace.
  static Never throwWithStackTrace(Object error, StackTrace stackTrace) =>
      Error.throwWithStackTrace(error, stackTrace);
}
