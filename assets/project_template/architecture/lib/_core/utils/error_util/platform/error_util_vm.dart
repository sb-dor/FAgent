// The crash reporter of Android, iOS and desktop. Nothing is sent until one is added: with
// `firebase_crashlytics` (after `flutterfire configure`), for example, with its library and
// `flutter/foundation.dart` imported:
//
// Future<void> $captureException(Object exception, StackTrace stackTrace, String? hint, bool fatal) {
//   // Crashlytics supports Android and iOS; use another service (Sentry) for desktop.
//   final mobile = defaultTargetPlatform == TargetPlatform.android ||
//       defaultTargetPlatform == TargetPlatform.iOS;
//   if (!kReleaseMode || !mobile) return Future<void>.value();
//   return FirebaseCrashlytics.instance.recordError(exception, stackTrace, reason: hint, fatal: fatal);
// }
//
// Future<void> $captureMessage(String message, StackTrace? stackTrace, String? hint, bool warning) =>
//     warning || stackTrace != null
//         ? FirebaseCrashlytics.instance.recordError(
//             message,
//             stackTrace ?? StackTrace.current,
//             reason: hint,
//           )
//         : FirebaseCrashlytics.instance.log('$message${hint != null ? '\n$hint' : ''}');
//
// Errors the app expects are not crashes: return early for them. An expired session
// (`APIClientException$Authorization` from `api_client.dart`) is one: the authentication middleware
// refreshes the token or signs the user out.

/// Sends [exception] to the crash reporter.
Future<void> $captureException(Object exception, StackTrace stackTrace, String? hint, bool fatal) =>
    Future<void>.value();

/// Sends [message] to the crash reporter: as an error when it is a [warning] or has a
/// [stackTrace], otherwise as a breadcrumb.
Future<void> $captureMessage(String message, StackTrace? stackTrace, String? hint, bool warning) =>
    Future<void>.value();
