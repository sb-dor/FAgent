import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:{{package}}/_core/telemetry/crash_reporter.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'without flutterfire configure there is no gateway and the failure is logged once',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final hints = <String?>[];
      var initialized = 0;

      final gateway = await createCrashReportGateway(
        projectPackages: const <String>{'{{package}}'},
        initializeFirebase: () async {
          initialized++;
          throw FirebaseException(plugin: 'core', code: 'not-initialized');
        },
        logError: (error, stackTrace, {hint, fatal = false}) async => hints.add(hint),
      );

      expect(gateway, isNull);
      expect(initialized, 1);
      expect(hints, <String?>['Firebase is not configured']);
    },
  );

  test('where Crashlytics does not run, Firebase is not started', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    var initialized = 0;

    final gateway = await createCrashReportGateway(
      projectPackages: const <String>{'{{package}}'},
      initializeFirebase: () async => initialized++,
      logError: (error, stackTrace, {hint, fatal = false}) async => fail('nothing to log'),
    );

    // No SENTRY_DSN in a test run: no Sentry either.
    expect(gateway, isNull);
    expect(initialized, 0);
  });
}
