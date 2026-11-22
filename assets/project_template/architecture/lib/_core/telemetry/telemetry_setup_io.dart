import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:{{package}}/_core/telemetry/crash_report_gateway.dart';
import 'package:{{package}}/_core/telemetry/crash_reporter.dart';
import 'package:{{package}}/_core/telemetry/error_hub.dart';
import 'package:{{package}}/_core/telemetry/error_outbox.dart';
import 'package:{{package}}/_core/telemetry/start_telemetry.dart';
import 'package:{{package}}/_core/telemetry/telemetry_runtime.dart';

export 'package:{{package}}/_core/telemetry/telemetry_runtime.dart' show TelemetryRuntime;

/// The app-wide hub of `ErrorUtil`; [startTelemetryLog] connects the log to it.
final ErrorHub _hub = ErrorHub();

/// Writes [error] to the log and, unless it is expected, to the queue of the crash reporter.
Future<void> reportError(Object error, StackTrace stackTrace, {String? hint, bool fatal = false}) =>
    _hub.logError(error, stackTrace, hint: hint, fatal: fatal);

/// Writes [message] to the log; a [warning] also goes to the queue.
Future<void> reportMessage(
  String message, {
  StackTrace? stackTrace,
  String? hint,
  bool warning = false,
}) => _hub.logMessage(message, stackTrace: stackTrace, hint: hint, warning: warning);

/// Waits until every started report is written.
Future<void> reportsSettled() => _hub.settled();

/// Whether [error] is a dropped connection.
bool isSocketException(Object error) => error is SocketException;

/// Opens `logs.sqlite` in the application support directory and connects the log, the queue and
/// the sender to `ErrorUtil`; their shutdown goes to [defer], in order.
///
/// Returns `null` when the log cannot be opened: the app works without it and errors go to the
/// console. The project has no user switch, so sending is on whenever the crash reporter is
/// configured (the developer who sets the DSN owns the reports), and nothing filters by a moment of
/// consent. An app that gets a switch passes its setting and consent time instead (see "Crash
/// reports" in docs/rules/security.md).
Future<TelemetryRuntime?> startTelemetryLog({
  required String appVersion,
  required bool Function(Object error) isExpected,
  required Set<String> projectPackages,
  required void Function(String name, Future<void> Function() step) defer,
}) async {
  final gateway = await createCrashReportGateway(projectPackages: projectPackages);
  Future<void> release() async {
    if (gateway != null) await closeCrashReportGateway(gateway);
  }

  final runtime = await startTelemetry(
    supportDirectory: getApplicationSupportDirectory,
    hub: _hub,
    gateway: gateway ?? const _NoCrashReporter(),
    reporterConfigured: gateway != null && crashReporterConfigured,
    appVersion: appVersion,
    isExpected: isExpected,
    projectPackages: projectPackages,
    enabled: true,
    releaseGateway: release,
    defer: defer,
  );
  // After the log: closing the log may still report.
  defer('Close the crash reporter', release);
  return runtime;
}

/// The gateway of a project without a crash reporter: the log and the queue are kept, nothing is
/// sent.
final class _NoCrashReporter implements ICrashReportGateway {
  const _NoCrashReporter();

  @override
  Future<bool> reachable() async => false;

  @override
  Future<bool> send(OutboxEntry entry) async => false;
}
