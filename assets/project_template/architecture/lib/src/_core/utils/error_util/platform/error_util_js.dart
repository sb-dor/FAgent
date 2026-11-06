// The crash reporter of the web. Crashlytics has no web support; Sentry works on the web and the
// VM alike. Nothing is sent until one is added, for example with `sentry_flutter`:
//
// Future<void> $captureException(Object exception, StackTrace stackTrace, String? hint, bool fatal) =>
//     Sentry.captureException(exception, stackTrace: stackTrace);
//
// Future<void> $captureMessage(String message, StackTrace? stackTrace, String? hint, bool warning) =>
//     Sentry.captureMessage(message, level: warning ? SentryLevel.warning : SentryLevel.info);

/// Sends [exception] to the crash reporter.
Future<void> $captureException(Object exception, StackTrace stackTrace, String? hint, bool fatal) =>
    Future<void>.value();

/// Sends [message] to the crash reporter: as an error when it is a [warning] or has a
/// [stackTrace], otherwise as a breadcrumb.
Future<void> $captureMessage(String message, StackTrace? stackTrace, String? hint, bool warning) =>
    Future<void>.value();
