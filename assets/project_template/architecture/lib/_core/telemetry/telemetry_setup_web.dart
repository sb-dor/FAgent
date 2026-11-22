import 'package:l/l.dart';
import 'package:{{package}}/_core/telemetry/redact.dart';

/// The web has no error log: this type only lets `Dependencies.telemetryRuntime` compile, and the
/// field stays `null`.
abstract final class TelemetryRuntime {
  /// Turns sending on or off (a user's switch); see `telemetry_runtime.dart` on the VM.
  Future<void> setEnabled(bool enabled, {DateTime? since});
}

/// Writes [error] to the console.
Future<void> reportError(
  Object error,
  StackTrace stackTrace, {
  String? hint,
  bool fatal = false,
}) async => l.e(redactSecrets(hint == null ? '$error' : '$hint: $error'), stackTrace);

/// Writes [message] to the console.
Future<void> reportMessage(
  String message, {
  StackTrace? stackTrace,
  String? hint,
  bool warning = false,
}) async {
  final text = redactSecrets(hint == null ? message : '$hint: $message');
  warning ? l.w(text, stackTrace ?? StackTrace.current) : l.i(text);
}

/// Nothing is written in the background on the web.
Future<void> reportsSettled() async {}

/// The web has no `SocketException`.
bool isSocketException(Object error) => false;

/// The web has no error log: always `null`.
Future<TelemetryRuntime?> startTelemetryLog({
  required String appVersion,
  required bool Function(Object error) isExpected,
  required Set<String> projectPackages,
  required void Function(String name, Future<void> Function() step) defer,
}) async => null;
