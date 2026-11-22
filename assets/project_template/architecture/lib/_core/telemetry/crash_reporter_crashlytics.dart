import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:{{package}}/_core/constant/config.dart';
import 'package:{{package}}/_core/telemetry/crash_report_gateway.dart';
import 'package:{{package}}/_core/telemetry/crashlytics_gateway.dart';
import 'package:{{package}}/_core/telemetry/error_util.dart';
import 'package:{{package}}/_core/telemetry/sentry_gateway.dart';

/// Reports an error, as `ErrorUtil.logError` does.
typedef ReportError = Future<void> Function(
  Object error,
  StackTrace stackTrace, {
  String? hint,
  bool fatal,
});

/// Whether `firebase_crashlytics` runs here: Android, iOS and macOS.
bool get _crashlyticsPlatform =>
    !kIsWeb &&
    switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.macOS => true,
      TargetPlatform.fuchsia || TargetPlatform.linux || TargetPlatform.windows => false,
    };

/// Whether the build has a crash reporter: Crashlytics on Android, iOS and macOS (connected by
/// `flutterfire configure`), elsewhere a Sentry DSN from `config/sentry.local.json` (see "The
/// Sentry DSN" in docs/rules/configuration.md). Without one nothing is sent; the log and the queue
/// are still kept.
bool get crashReporterConfigured => _crashlyticsPlatform || Config.sentryDsn.trim().isNotEmpty;

/// The link to Crashlytics on Android, iOS and macOS, to Sentry elsewhere when a DSN is set, else
/// `null`. [projectPackages] are the packages of the project: Sentry marks their frames as its own.
///
/// Firebase starts here, once. Until `flutterfire configure` has connected the project it fails:
/// the failure goes to the log ([logError], `ErrorUtil.logError` unless a test gives one) and the
/// app runs with the log only. Once it starts, Crashlytics collection is turned off: the gateway
/// turns it on at its first send, when sending is on. [initializeFirebase] replaces
/// `Firebase.initializeApp` and [createGateway] the gateway on the default instance in tests.
Future<ICrashReportGateway?> createCrashReportGateway({
  required Set<String> projectPackages,
  @visibleForTesting Future<Object?> Function() initializeFirebase = Firebase.initializeApp,
  @visibleForTesting CrashlyticsGateway Function() createGateway = CrashlyticsGateway.new,
  @visibleForTesting ReportError logError = ErrorUtil.logError,
}) async {
  if (!_crashlyticsPlatform) {
    return Config.sentryDsn.trim().isEmpty
        ? null
        : SentryGateway(
            dsn: Config.sentryDsn,
            projectPackages: projectPackages,
            environment: Config.environment.value,
            release: Config.appVersion,
          );
  }
  try {
    await initializeFirebase();
  } on Exception catch (error, stackTrace) {
    // Not connected yet (`flutterfire configure`): the errors stay in the log until it is.
    await logError(error, stackTrace, hint: 'Firebase is not configured');
    return null;
  }
  final gateway = createGateway();
  try {
    // Native Crashlytics collects unless told not to, and the last switch persists.
    await gateway.stopCollecting();
  } on Exception catch (error, stackTrace) {
    // Collection may be on: no gateway, so this app sends nothing to Crashlytics.
    await logError(error, stackTrace, hint: 'Crashlytics collection could not be turned off');
    return null;
  }
  return gateway;
}

/// Closes [gateway] (on exit, or when a user's switch turns sending off): Sentry flushes and stops;
/// Crashlytics stops collecting until the next send.
Future<void> closeCrashReportGateway(ICrashReportGateway gateway) async {
  if (gateway is SentryGateway) await gateway.close();
  if (gateway is CrashlyticsGateway) await gateway.stopCollecting();
}
