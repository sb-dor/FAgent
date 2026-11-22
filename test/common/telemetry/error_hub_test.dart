import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/telemetry/crash_report_gateway.dart';
import 'package:flutter_code_agent/src/common/telemetry/error_hub.dart';
import 'package:flutter_code_agent/src/common/telemetry/error_outbox.dart';
import 'package:flutter_code_agent/src/common/telemetry/telemetry_database.dart';
import 'package:flutter_code_agent/src/common/telemetry/telemetry_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l/l.dart';

TelemetryRuntime _runtime({bool Function(Object)? isExpected}) {
  final db = TelemetryDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  return TelemetryRuntime(
    db: db,
    gateway: _NoGateway(),
    appVersion: '1.0.0',
    platform: 'test',
    isExpected: isExpected ?? (e) => e is TimeoutException,
    projectPackages: const {'my_app'},
    enabled: true,
  );
}

final class _NoGateway implements ICrashReportGateway {
  @override
  Future<bool> reachable() async => false;

  @override
  Future<bool> send(OutboxEntry entry) async => false;
}

Future<T> _quiet<T extends Object?>(Future<T> Function() body) =>
    // ignore: experimental_member_use
    l.capture(body, const LogOptions(output: LogOutput.ignore, handlePrint: false));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late ErrorHub hub;
  late List<String> console;

  setUp(() {
    console = [];
    hub = ErrorHub(console: console.add);
    addTearDown(hub.reset);
  });

  test('before configure an error is written to the console and waits in memory', () async {
    await _quiet(() async {
      await hub.logError(StateError('early'), StackTrace.current);

      expect(console.single, contains('early'));
    });
  });

  test(
    'configure flushes early errors to the queue with the original time and log lines',
    () async {
      await _quiet(() async {
        final runtime = _runtime();
        l.i('line before the error');
        await pumpEventQueue();
        final before = DateTime.now().toUtc();
        await hub.logError(StateError('early'), StackTrace.current, hint: 'H', fatal: true);
        await Future<void>.delayed(const Duration(milliseconds: 30));

        hub.configure(runtime);
        await hub.settled();

        final entry = (await runtime.outbox.oldest(5)).single;
        expect((entry.hint, entry.level), ('H', 'fatal'));
        expect(entry.firstAt.isBefore(before.add(const Duration(milliseconds: 25))), isTrue);
        expect(entry.breadcrumbs.join('\n'), contains('line before the error'));
      });
    },
  );

  test('up to 100 early errors: the oldest are pushed out', () async {
    await _quiet(() async {
      final runtime = _runtime();
      for (var i = 0; i < 105; i++) {
        await hub.logError(StateError('early $i'), StackTrace.current, hint: 'H$i');
      }
      hub.configure(runtime);
      await hub.settled();

      final queue = await runtime.outbox.oldest(200);
      expect(queue.fold<int>(0, (sum, e) => sum + e.count), ErrorHub.pendingLimit);
    });
  });

  test('an expected error is only in the log, an unexpected one in the queue', () async {
    await _quiet(() async {
      final runtime = _runtime();
      hub.configure(runtime);

      await hub.logError(TimeoutException('slow'), StackTrace.current);
      await hub.logError(StateError('failure'), StackTrace.current);

      expect((await runtime.outbox.oldest(5)).map((e) => e.type), ['StateError']);
    });
  });

  test('disconnect: after the log is closed errors pile up in memory again', () async {
    await _quiet(() async {
      final runtime = _runtime();
      hub.configure(runtime);
      await hub.settled();
      hub.disconnect(runtime);

      await hub.logError(StateError('after close'), StackTrace.current);

      expect(await runtime.outbox.length(), 0);
    });
  });

  test('early log lines do not carry over into errors after configure and disconnect', () async {
    await _quiet(() async {
      final first = _runtime();
      final second = _runtime();
      l.i('line of the former log');
      await pumpEventQueue();
      hub.configure(first);
      await hub.settled();
      hub.disconnect(first);

      await hub.logError(StateError('after close'), StackTrace.current);
      hub.configure(second);
      await hub.settled();

      final entry = (await second.outbox.oldest(5)).single;
      expect(entry.breadcrumbs.join('\n'), isNot(contains('line of the former log')));
    });
  });

  test('disconnect of a foreign log disconnects nothing', () async {
    await _quiet(() async {
      final runtime = _runtime();
      hub
        ..configure(runtime)
        ..disconnect(_runtime());

      await hub.logError(StateError('alive'), StackTrace.current);

      expect(await runtime.outbox.length(), 1);
    });
  });

  test('a secret in the error text does not reach the queue', () async {
    await _quiet(() async {
      final runtime = _runtime();
      hub.configure(runtime);

      await hub.logError(StateError('request with Bearer abcdef123456 failed'), StackTrace.current);

      final entry = (await runtime.outbox.oldest(1)).single;
      expect(entry.message, isNot(contains('abcdef123456')));
    });
  });
}
