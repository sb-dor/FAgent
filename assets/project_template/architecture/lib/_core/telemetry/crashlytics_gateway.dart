import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:{{package}}/_core/telemetry/crash_report_gateway.dart';
import 'package:{{package}}/_core/telemetry/error_outbox.dart';

/// The link of the app to Firebase Crashlytics (Android, iOS and macOS), behind the queue: an entry
/// comes here cleaned of secrets, merged with its repeats, and only once sending is on. Flutter
/// and zone errors never go to Crashlytics directly; they go through `ErrorUtil` like every other
/// error (see "Crash reports" in docs/rules/security.md).
///
/// Collection is off until the first send (`createCrashReportGateway` turns it off once Firebase
/// starts, and the new project's `Info.plist` and `AndroidManifest.xml` keep it off before that):
/// the sender sends only when telemetry is enabled. [stopCollecting] turns it off again.
/// `Firebase.initializeApp` must have succeeded before the gateway is made (`crash_reporter.dart`).
final class CrashlyticsGateway implements ICrashReportGateway {
  /// Creates the gateway on `crashlytics`, the default instance unless a test gives one.
  CrashlyticsGateway({this._crashlytics});

  final FirebaseCrashlytics? _crashlytics;
  Future<void>? _collecting;

  FirebaseCrashlytics get _instance => _crashlytics ?? FirebaseCrashlytics.instance;

  /// Crashlytics keeps a report until it can upload it, so there is nothing to check.
  @override
  Future<bool> reachable() async => true;

  @override
  Future<bool> send(OutboxEntry entry) async {
    await _collect();
    for (final line in entry.breadcrumbs) {
      await _instance.log(line);
    }
    await _instance.recordError(
      '${entry.type}: ${entry.message}',
      StackTrace.fromString(entry.stack),
      reason: entry.hint,
      fatal: entry.level == 'fatal',
      // The log already printed it.
      printDetails: false,
    );
    return true;
  }

  /// Turns collection off: when sending is turned off, on exit, and once Firebase starts. The next
  /// [send] turns it on again. The setting persists across launches.
  Future<void> stopCollecting() async {
    _collecting = null;
    await _instance.setCrashlyticsCollectionEnabled(false);
  }

  /// Turns collection on once; a failed attempt is not kept, the next send tries again.
  Future<void> _collect() async {
    final collecting = _collecting ??= _instance.setCrashlyticsCollectionEnabled(true);
    try {
      await collecting;
    } on Object {
      if (identical(_collecting, collecting)) _collecting = null;
      rethrow;
    }
  }
}
