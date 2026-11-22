import 'dart:async';

import 'package:l/l.dart';

/// Runs [fn] in the log zone: `print` goes to the log, and an unhandled error goes to [onError]
/// instead of vanishing.
///
/// The default [options] turn the console output off in release (the log and the queue are kept)
/// and handle `print`.
void logZone(
  Future<void> Function() fn, {
  required void Function(Object error, StackTrace stack) onError,
  LogOptions options = LogOptions.defaultOptions,
}) {
  // ignore: experimental_member_use
  l.capture(() => runZonedGuarded<void>(() => unawaited(fn()), onError), options);
}
