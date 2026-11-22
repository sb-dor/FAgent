import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:{{package}}/_core/telemetry/crash_reporter.dart';
import 'package:{{package}}/_core/telemetry/crashlytics_gateway.dart';
import 'package:{{package}}/_core/telemetry/error_outbox.dart';

/// Crashlytics without the platform: records the collection switches and the reports.
final class _FakeCrashlytics extends Fake implements FirebaseCrashlytics {
  /// Every value given to `setCrashlyticsCollectionEnabled`, in order.
  final List<bool> collection = <bool>[];

  /// How many reports were recorded.
  int recorded = 0;

  /// The next `setCrashlyticsCollectionEnabled(true)` fails once.
  bool failNextEnable = false;

  @override
  Future<void> setCrashlyticsCollectionEnabled(bool enabled) async {
    collection.add(enabled);
    if (enabled && failNextEnable) {
      failNextEnable = false;
      throw PlatformException(code: 'unavailable');
    }
  }

  @override
  Future<void> log(String message) async {}

  @override
  Future<void> recordError(
    Object? exception,
    StackTrace? stack, {
    Object? reason,
    Iterable<Object> information = const <Object>[],
    bool? printDetails,
    bool fatal = false,
  }) async => recorded++;
}

OutboxEntry _entry() => OutboxEntry(
  id: 1,
  fingerprint: 'f',
  firstAt: DateTime.utc(2026),
  lastAt: DateTime.utc(2026),
  count: 1,
  attempts: 0,
  level: 'error',
  type: 'StateError',
  message: 'Bad state: x',
  stack: '#0 main (package:{{package}}/main.dart:1:1)',
  hint: null,
  breadcrumbs: const <String>['2026-01-01T00:00:00.000Z [I] line'],
  appVersion: '1.0.0',
  platform: 'android',
);

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

  test('once Firebase starts, collection is off until the first send', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final crashlytics = _FakeCrashlytics();

    final gateway = await createCrashReportGateway(
      projectPackages: const <String>{'{{package}}'},
      initializeFirebase: () async => null,
      crashlytics: crashlytics,
      logError: (error, stackTrace, {hint, fatal = false}) async => fail('nothing to log'),
    );

    expect(gateway, isA<CrashlyticsGateway>());
    expect(crashlytics.collection, <bool>[false]);
  });

  test('sending turns collection on once, closing turns it off until the next send', () async {
    final crashlytics = _FakeCrashlytics();
    final gateway = CrashlyticsGateway(crashlytics: crashlytics);

    expect(await gateway.send(_entry()), isTrue);
    expect(await gateway.send(_entry()), isTrue);
    expect(crashlytics.collection, <bool>[true]);

    await closeCrashReportGateway(gateway);
    expect(crashlytics.collection, <bool>[true, false]);

    expect(await gateway.send(_entry()), isTrue);
    expect(crashlytics.collection, <bool>[true, false, true]);
    expect(crashlytics.recorded, 3);
  });

  test('a failed turn on is tried again at the next send', () async {
    final crashlytics = _FakeCrashlytics()..failNextEnable = true;
    final gateway = CrashlyticsGateway(crashlytics: crashlytics);

    await expectLater(gateway.send(_entry()), throwsA(isA<PlatformException>()));
    expect(crashlytics.recorded, 0);

    expect(await gateway.send(_entry()), isTrue);
    expect(crashlytics.collection, <bool>[true, true]);
    expect(crashlytics.recorded, 1);
  });
}
