// The class groups the logging helpers under one name at every call site (`ErrorUtil.logError`).
// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';

import 'package:l/l.dart';
import 'package:{{package}}/src/_core/utils/error_util/platform/error_util_vm.dart'
    if (dart.library.js_interop) 'package:{{package}}/src/_core/utils/error_util/platform/error_util_js.dart';

/// Error utils.
abstract final class ErrorUtil {
  /// Logs the error to the console and to the crash reporter.
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
      // Sends the exception to the crash reporter (Crashlytics, Sentry): see platform/.
      $captureException(exception, stackTrace, hint, fatal).ignore();
      l.e(hint == null ? exception : '$hint\n$exception', stackTrace);
    } on Object catch (error, stackTrace) {
      l.e('Error while logging error "$error" inside ErrorUtil.logError', stackTrace);
    }
  }

  /// Logs a message to the console and to the crash reporter.
  static Future<void> logMessage(
    String message, {
    StackTrace? stackTrace,
    String? hint,
    bool warning = false,
  }) async {
    try {
      final text = hint == null ? message : '$hint\n$message';
      warning ? l.w(text, stackTrace ?? StackTrace.current) : l.i(text);
      $captureMessage(message, stackTrace, hint, warning).ignore();
    } on Object catch (error, stackTrace) {
      l.e('Error while logging error "$error" inside ErrorUtil.logMessage', stackTrace);
    }
  }

  /// Rethrows the error with the stack trace.
  static Never throwWithStackTrace(Object error, StackTrace stackTrace) =>
      Error.throwWithStackTrace(error, stackTrace);
}
