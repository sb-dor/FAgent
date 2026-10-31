/// {@template flutter_not_found_exception}
/// No Flutter SDK could be found: neither the project's fvm SDK nor `flutter`
/// on the `PATH`.
/// {@endtemplate}
final class FlutterNotFoundException implements Exception {
  /// {@macro flutter_not_found_exception}
  const FlutterNotFoundException();

  @override
  String toString() => 'FlutterNotFoundException: Flutter SDK not found';
}

/// {@template daemon_closed_exception}
/// The daemon process exited (or was closed) before it answered [method].
/// {@endtemplate}
final class DaemonClosedException implements Exception {
  /// {@macro daemon_closed_exception}
  const DaemonClosedException({this.method});

  /// The request that was left without an answer, if any.
  final String? method;

  @override
  String toString() => method == null
      ? 'DaemonClosedException: the Flutter daemon is not running'
      : 'DaemonClosedException: the Flutter daemon exited before answering $method';
}

/// {@template daemon_request_exception}
/// The daemon answered [method] with an `error`.
/// {@endtemplate}
final class DaemonRequestException implements Exception {
  /// {@macro daemon_request_exception}
  const DaemonRequestException({required this.method, required this.error});

  /// The request that failed.
  final String method;

  /// The `error` value of the response, as the daemon sent it.
  final Object? error;

  @override
  String toString() => 'DaemonRequestException: $method failed: $error';
}
