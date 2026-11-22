import 'package:{{package}}/_core/constant/config.dart';
import 'package:{{package}}/_core/telemetry/crash_report_gateway.dart';
import 'package:{{package}}/_core/telemetry/sentry_gateway.dart';

/// Whether the build has a crash reporter: a Sentry DSN from `config/sentry.local.json` (see "The
/// Sentry DSN" in docs/rules/configuration.md). Without one nothing is sent; the log and the queue
/// are still kept, so the errors are there once a DSN is set.
bool get crashReporterConfigured => Config.sentryDsn.trim().isNotEmpty;

/// The link to Sentry, on plain `sentry` (no native part); `null` without a DSN. [projectPackages]
/// are the packages of the project: their frames are marked as its own.
Future<ICrashReportGateway?> createCrashReportGateway({
  required Set<String> projectPackages,
}) async => crashReporterConfigured
    ? SentryGateway(
        dsn: Config.sentryDsn,
        projectPackages: projectPackages,
        environment: Config.environment.value,
        release: Config.appVersion,
      )
    : null;

/// Closes [gateway] (on exit, or when a user's switch turns sending off): Sentry flushes and stops.
Future<void> closeCrashReportGateway(ICrashReportGateway gateway) async {
  if (gateway is SentryGateway) await gateway.close();
}
