import 'dart:async';

import 'package:l/l.dart';

/// Logs [exception] to the console.
///
/// Crash reporting (Sentry or similar) plugs in here once the app is released.
Future<void> logError(
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
    l.e('Error while logging error "$error" inside logError', stackTrace);
  }
}

/// Logs [message] to the console.
Future<void> logMessage(
  String message, {
  StackTrace? stackTrace,
  String? hint,
  bool warning = false,
}) async {
  try {
    final text = hint == null ? message : '$hint\n$message';
    warning ? l.w(text, stackTrace) : l.i(text);
  } on Object catch (error, stackTrace) {
    l.e('Error while logging error "$error" inside logMessage', stackTrace);
  }
}
