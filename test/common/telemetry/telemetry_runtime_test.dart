import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/telemetry/crash_report_gateway.dart';
import 'package:flutter_code_agent/src/common/telemetry/error_outbox.dart';
import 'package:flutter_code_agent/src/common/telemetry/telemetry_database.dart';
import 'package:flutter_code_agent/src/common/telemetry/telemetry_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l/l.dart';

final class _NoGateway implements ICrashReportGateway {
  @override
  Future<bool> reachable() async => false;

  @override
  Future<bool> send(OutboxEntry entry) async => false;
}

/// A test whose log output is swallowed: the test output stays pristine.
void _test(String name, Future<void> Function() body) => test(
  name,
  // ignore: experimental_member_use
  () => l.capture(body, const LogOptions(output: LogOutput.ignore, handlePrint: false)),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  _raceTest();
  _test('resetData waits for the started records: the queue is empty after the reset', () async {
    final db = TelemetryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final runtime = TelemetryRuntime(
      db: db,
      gateway: _NoGateway(),
      appVersion: '1.0.0',
      platform: 'test',
      projectPackages: const {'my_app'},
      isExpected: (_) => false,
      enabled: true,
    );
    runtime.reporter.console = (_) {};

    // ignore: experimental_member_use
    await l.capture(() async {
      // A record is started but not finished: without waiting it would reach the queue after the reset.
      final pending = runtime.reporter.logError(StateError('former device'), StackTrace.current);

      await runtime.resetData();
      await pending;

      expect(await runtime.outbox.length(), 0);
    }, const LogOptions(output: LogOutput.ignore, handlePrint: false));
  });

  _test('settled waits for the queue counter refresh too', () async {
    final db = TelemetryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final runtime = TelemetryRuntime(
      db: db,
      gateway: _NoGateway(),
      appVersion: '1.0.0',
      platform: 'test',
      projectPackages: const {'my_app'},
      isExpected: (_) => false,
      enabled: true,
    );
    runtime.reporter.console = (_) {};

    await runtime.reporter.logError(StateError('failure'), StackTrace.current);
    await runtime.settled();

    expect(runtime.sender.current.queued, 1);
  });

  _test('M2: setEnabled(true) starts a pass, setEnabled(false) closes the gateway', () async {
    final db = TelemetryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final gateway = _CountingGateway();
    var released = 0;
    final runtime = TelemetryRuntime(
      db: db,
      gateway: gateway,
      appVersion: '1.0.0',
      platform: 'test',
      projectPackages: const {'my_app'},
      isExpected: (_) => false,
      releaseGateway: () async => released++,
    );
    runtime.reporter.console = (_) {};
    await runtime.reporter.logError(StateError('waiting'), StackTrace.current);
    await runtime.settled();

    await runtime.setEnabled(true);
    // The extra pass is already started: wait for it.
    for (var i = 0; i < 100 && gateway.sent == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(gateway.sent, 1);
    expect(runtime.toggle.enabled, isTrue);
    expect(released, 0);

    await runtime.setEnabled(true);
    expect(released, 0);

    await runtime.setEnabled(false);
    expect(runtime.toggle.enabled, isFalse);
    expect(released, 1);
  });

  _test(
    'F9: setEnabled(false) closes the gateway only after the running pass has stopped',
    () async {
      final db = TelemetryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final events = <String>[];
      final gateway = _SlowGateway(events);
      final runtime = TelemetryRuntime(
        db: db,
        gateway: gateway,
        appVersion: '1.0.0',
        platform: 'test',
        projectPackages: const {'my_app'},
        isExpected: (_) => false,
        enabled: true,
        releaseGateway: () async => events.add('close'),
      );
      runtime.reporter.console = (_) {};
      await runtime.reporter.logError(StateError('waiting'), StackTrace.current);
      await runtime.settled();
      unawaited(runtime.sender.runPass());
      while (!events.contains('send start')) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      await runtime.setEnabled(false);

      expect(events, ['send start', 'send end', 'close']);
    },
  );
}

void _raceTest() {
  _test('quick off and on: the gateway closes before the new pass, sending goes on', () async {
    final db = TelemetryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final events = <String>[];
    final runtime = TelemetryRuntime(
      db: db,
      gateway: _SlowGateway(events),
      appVersion: '1.0.0',
      platform: 'test',
      projectPackages: const {'my_app'},
      isExpected: (_) => false,
      enabled: true,
      releaseGateway: () async => events.add('close'),
    );
    runtime.reporter.console = (_) {};
    await runtime.reporter.logError(StateError('first'), StackTrace.current);
    await runtime.reporter.logError(ArgumentError('second'), StackTrace.current);
    await runtime.settled();
    unawaited(runtime.sender.runPass());
    while (!events.contains('send start')) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    final off = runtime.setEnabled(false);
    final on = runtime.setEnabled(true);
    await off;
    await on;
    while (events.where((e) => e == 'send end').length < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(events.indexOf('close'), lessThan(events.lastIndexOf('send start')));
    expect(events.last, 'send end');
    expect(runtime.toggle.enabled, isTrue);
    unawaited(runtime.sender.dispose());
  });
}

final class _SlowGateway implements ICrashReportGateway {
  _SlowGateway(this.events);

  final List<String> events;

  @override
  Future<bool> reachable() async => true;

  @override
  Future<bool> send(OutboxEntry entry) async {
    events.add('send start');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    events.add('send end');
    return true;
  }
}

final class _CountingGateway implements ICrashReportGateway {
  int sent = 0;

  @override
  Future<bool> reachable() async => true;

  @override
  Future<bool> send(OutboxEntry entry) async {
    sent++;
    return true;
  }
}
