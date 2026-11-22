import 'package:{{package}}/_core/telemetry/crash_report_gateway.dart';

/// The project reports to no service: unexpected errors stay in the log (`logs.sqlite`) and the
/// queue on the device, where a settings screen or the log archive shows them. To send them, put a
/// gateway here (see "Crash reports" in docs/rules/security.md); the rest of the pipeline stays.
bool get crashReporterConfigured => false;

/// No crash reporter: always `null`.
Future<ICrashReportGateway?> createCrashReportGateway({
  required Set<String> projectPackages,
}) async => null;

/// Nothing to close.
Future<void> closeCrashReportGateway(ICrashReportGateway gateway) async {}
