import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_code_agent/_core/telemetry/crash_report_gateway.dart';
import 'package:flutter_code_agent/_core/telemetry/error_outbox.dart';
import 'package:flutter_code_agent/_core/telemetry/telemetry_database.dart';
import 'package:flutter_code_agent/_core/telemetry/telemetry_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l/l.dart';

final class _RecordingGateway implements ICrashReportGateway {
  final List<OutboxEntry> sent = [];

  /// Called at the start of every send; lets a test act mid-pass.
  Future<void> Function()? onSend;

  @override
  Future<bool> reachable() async => true;

  @override
  Future<bool> send(OutboxEntry entry) async {
    await onSend?.call();
    sent.add(entry);
    return true;
  }
}

final t0 = DateTime.utc(2026, 1, 1, 10);
final t1 = DateTime.utc(2026, 1, 1, 11);
final t2 = DateTime.utc(2026, 1, 1, 12);
final t3 = DateTime.utc(2026, 1, 1, 13);
final t4 = DateTime.utc(2026, 1, 1, 14);

/// A test whose log output is swallowed: the test output stays pristine.
void _test(
  String name,
  Future<void> Function(TelemetryRuntime runtime, _RecordingGateway gateway) body, {
  bool enabled = false,
  DateTime? consentSince,
}) {
  test(
    name,
    // ignore: experimental_member_use
    () => l.capture(() async {
      final db = TelemetryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final gateway = _RecordingGateway();
      final runtime = TelemetryRuntime(
        db: db,
        gateway: gateway,
        appVersion: '1.0.0',
        platform: 'test',
        projectPackages: const {'my_app'},
        isExpected: (_) => false,
        enabled: enabled,
        consentSince: consentSince,
      );
      addTearDown(runtime.sender.dispose);
      await body(runtime, gateway);
      await runtime.settled();
    }, const LogOptions(output: LogOutput.ignore, handlePrint: false)),
  );
}

Future<void> _add(
  TelemetryRuntime runtime,
  Object error,
  DateTime at, {
  List<String> breadcrumbs = const [],
}) => runtime.outbox.add(
  error: error,
  stack: StackTrace.fromString('#0 main (package:my_app/main.dart:1:1)'),
  level: 'error',
  breadcrumbs: breadcrumbs,
  at: at,
);

/// Waits for the pass that turning on started, then runs one more over the current queue.
Future<void> _pass(TelemetryRuntime runtime) async {
  await runtime.sender.stop();
  await runtime.sender.runPass();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  _test('entries from before consent are never sent', (runtime, gateway) async {
    await _add(runtime, StateError('a'), t0);
    await _add(runtime, ArgumentError('b'), t0);
    await _add(runtime, UnsupportedError('c'), t0);

    await runtime.setEnabled(true, since: t1);
    await _pass(runtime);

    expect(gateway.sent, isEmpty);
    expect(await runtime.outbox.length(), 3);
  });

  _test('a recurrence after consent sends only the new occurrence', (runtime, gateway) async {
    await _add(runtime, StateError('same'), t0, breadcrumbs: ['${t0.toIso8601String()} [I] old']);
    await runtime.setEnabled(true, since: t1);
    await _add(runtime, StateError('same'), t2, breadcrumbs: ['${t2.toIso8601String()} [I] new']);

    await _pass(runtime);

    expect(gateway.sent, hasLength(1));
    final entry = gateway.sent.single;
    expect(entry.count, 1);
    expect(entry.firstAt, t2);
    expect(entry.lastAt, t2);
    expect(entry.breadcrumbs, ['${t2.toIso8601String()} [I] new']);
    expect(entry.attempts, 0);
  });

  _test('an error after consent is sent', (runtime, gateway) async {
    await runtime.setEnabled(true, since: t1);
    await _add(runtime, StateError('later'), t2);

    await _pass(runtime);

    expect(gateway.sent, hasLength(1));
  });

  _test('no consent time sends everything', (runtime, gateway) async {
    await _add(runtime, StateError('old'), t0);

    await _pass(runtime);

    expect(gateway.sent, hasLength(1));
  }, enabled: true);

  _test('turning off and on again moves the consent', (runtime, gateway) async {
    await runtime.setEnabled(true, since: t1);
    await _add(runtime, StateError('e'), t2);
    await runtime.setEnabled(false);
    await _add(runtime, ArgumentError('f'), t3);
    await runtime.setEnabled(true, since: t4);
    await _pass(runtime);

    expect(gateway.sent.where((e) => e.type == 'ArgumentError'), isEmpty);
  });

  _test('consent moved later mid-pass: older entries of the running pass are not sent', (
    runtime,
    gateway,
  ) async {
    await _add(runtime, StateError('first'), t1);
    await _add(runtime, ArgumentError('second'), t2);
    await _add(runtime, UnsupportedError('third'), t3);
    var moved = false;
    gateway.onSend = () async {
      if (!moved) {
        moved = true;
        runtime.outbox.consentSince = t3.add(const Duration(minutes: 1));
      }
    };
    runtime.outbox.consentSince = t0;

    await runtime.sender.runPass();

    expect(gateway.sent.map((e) => e.type), ['StateError']);
  }, enabled: true);

  _test('moving since with the same enabled value applies it', (runtime, gateway) async {
    await runtime.setEnabled(true, since: t0);
    await runtime.sender.stop();
    await _add(runtime, StateError('x'), t1);
    await runtime.setEnabled(true, since: t2);
    await _pass(runtime);

    expect(gateway.sent, isEmpty);
  });

  _test('breadcrumbs written before consent are dropped', (runtime, gateway) async {
    await runtime.setEnabled(true, since: t1);
    await runtime.outbox.add(
      error: StateError('after'),
      stack: StackTrace.fromString('#0 main (package:my_app/main.dart:1:1)'),
      level: 'error',
      breadcrumbs: [
        '${t0.toIso8601String()} [I] before consent',
        '${t1.toIso8601String()} [I] at consent',
        '${t2.toIso8601String()} [E] after consent',
        'garbage without a time',
      ],
      at: t2,
    );
    await _pass(runtime);

    expect(gateway.sent.single.breadcrumbs, [
      '${t1.toIso8601String()} [I] at consent',
      '${t2.toIso8601String()} [E] after consent',
    ]);
  });

  _test('breadcrumbs kept before the consent time was known are dropped at send', (
    runtime,
    gateway,
  ) async {
    // The runtime started without a consent time (FAgent reads it later): the error is recorded
    // with every log line, the previous session's included.
    await _add(
      runtime,
      StateError('startup'),
      t2,
      breadcrumbs: [
        '${t0.toIso8601String()} [I] previous session',
        '${t2.toIso8601String()} [E] after consent',
      ],
    );

    await runtime.setEnabled(true, since: t1);
    await _pass(runtime);

    expect(gateway.sent.single.breadcrumbs, ['${t2.toIso8601String()} [E] after consent']);
  });

  _test('consent moved later mid-pass: breadcrumbs before it are not sent', (
    runtime,
    gateway,
  ) async {
    await _add(runtime, StateError('first'), t1);
    await _add(
      runtime,
      ArgumentError('second'),
      t4,
      breadcrumbs: ['${t2.toIso8601String()} [I] between', '${t4.toIso8601String()} [E] late'],
    );
    var moved = false;
    gateway.onSend = () async {
      if (!moved) {
        moved = true;
        runtime.outbox.consentSince = t3;
      }
    };
    runtime.outbox.consentSince = t0;

    await runtime.sender.runPass();

    expect(gateway.sent.map((e) => e.type), ['StateError', 'ArgumentError']);
    expect(gateway.sent.last.breadcrumbs, ['${t4.toIso8601String()} [E] late']);
  }, enabled: true);
}
