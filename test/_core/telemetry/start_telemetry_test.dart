import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_code_agent/_core/telemetry/crash_report_gateway.dart';
import 'package:flutter_code_agent/_core/telemetry/error_hub.dart';
import 'package:flutter_code_agent/_core/telemetry/error_outbox.dart';
import 'package:flutter_code_agent/_core/telemetry/log_storage.dart';
import 'package:flutter_code_agent/_core/telemetry/start_telemetry.dart';
import 'package:flutter_code_agent/_core/telemetry/telemetry_database.dart';
import 'package:flutter_code_agent/_core/telemetry/telemetry_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l/l.dart';

final class _Gateway implements ICrashReportGateway {
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

  late Directory dir;
  late ErrorHub hub;
  late List<String> console;
  late List<(String, Future<void> Function())> steps;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fagent_start_');
    console = [];
    hub = ErrorHub(console: console.add);
    steps = [];
    addTearDown(hub.reset);
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  Future<TelemetryRuntime?> start(Directory Function() where, {bool enabled = false}) =>
      startTelemetry(
        supportDirectory: () async => where(),
        hub: hub,
        gateway: _Gateway(),
        reporterConfigured: false,
        projectPackages: const {'my_app'},
        appVersion: '1.0.0',
        isExpected: (_) => false,
        defer: (name, step) => steps.add((name, step)),
        enabled: enabled,
      );

  test('logs.sqlite unavailable: null, the app works, logError does not throw', () async {
    await _quiet(() async {
      final blocker = File('${dir.path}/occupied')..writeAsStringSync('file');

      final runtime = await start(() => Directory(blocker.path));

      expect(runtime, isNull);
      await hub.logError(StateError('after the log failure'), StackTrace.current);
      expect(console.join('\n'), contains('after the log failure'));
    });
  });

  test('log opened: the error is in logs.sqlite and the queue, closing flushes the log', () async {
    await _quiet(() async {
      final runtime = await start(() => dir);

      expect(runtime, isNotNull);
      expect(File('${dir.path}/logs.sqlite').existsSync(), isTrue);
      await hub.logError(StateError('record me'), StackTrace.current);
      l.i('line before closing');
      for (final (_, step) in steps.reversed) {
        await step();
      }

      final db = openTelemetryDatabase(File('${dir.path}/logs.sqlite'));
      addTearDown(db.close);
      final stored = (await readStoredLogs(db)).map((m) => m.message.toString());
      expect(stored, contains('line before closing'));
      expect(
        (await ErrorOutbox(
          db,
          appVersion: '1',
          platform: 'x',
          projectPackages: const {'my_app'},
        ).oldest(5)).single.type,
        'StateError',
      );
    });
  });

  test(
    'resetData clears the queue, the buffer and the log on disk, including a batch not yet written',
    () async {
      await _quiet(() async {
        final runtime = (await start(() => dir))!;
        await hub.logError(StateError('foreign'), StackTrace.current);
        l.i('line of a foreign device');
        await Future<void>.delayed(Duration.zero);

        await runtime.resetData();

        expect(await runtime.outbox.length(), 0);
        expect(runtime.buffer.lastLines(10).join(), isNot(contains('foreign device')));
        for (final (_, step) in steps.reversed) {
          await step();
        }
        final db = openTelemetryDatabase(File('${dir.path}/logs.sqlite'));
        addTearDown(db.close);
        expect(
          (await readStoredLogs(db)).map((m) => m.message.toString()).join(),
          isNot(contains('foreign device')),
        );
      });
    },
  );
}
