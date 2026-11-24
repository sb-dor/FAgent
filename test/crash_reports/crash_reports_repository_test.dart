import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_code_agent/_core/telemetry/telemetry.dart';
import 'package:flutter_code_agent/crash_reports/data/crash_reports_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l/l.dart';

final class _NoGateway implements ICrashReportGateway {
  @override
  Future<bool> reachable() async => false;

  @override
  Future<bool> send(OutboxEntry entry) async => false;
}

const String _secret = 'sk-ant-api03-AbCdEf0123456789AbCdEf0123456789';

TelemetryRuntime _runtime() {
  final db = TelemetryDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  return TelemetryRuntime(
    db: db,
    gateway: _NoGateway(),
    appVersion: '1.0.0',
    platform: 'test',
    projectPackages: const <String>{'flutter_code_agent'},
    isExpected: (_) => false,
    consentSince: DateTime.utc(2026),
  );
}

Map<String, String> _unzip(String path) => <String, String>{
  for (final file in ZipDecoder().decodeBytes(File(path).readAsBytesSync()))
    file.name: utf8.decode(file.content),
};

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('crash_reports_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('recent gives at most 20 entries, newest first', () async {
    final runtime = _runtime();
    for (var i = 0; i < 25; i++) {
      await runtime.outbox.add(
        error: StateError('error $i'),
        stack: StackTrace.fromString('#0 f$i (package:flutter_code_agent/a.dart:$i:1)'),
        level: 'error',
        breadcrumbs: const <String>[],
        at: DateTime.utc(2026, 11, 22, 10, i),
      );
    }
    final repository = CrashReportsRepositoryImpl(runtime: runtime, configured: true);

    final recent = await repository.recent();

    expect(recent, hasLength(20));
    expect(recent.first.message, contains('error 24'));
    expect(recent.last.message, contains('error 5'));
    expect(await repository.recorded(), 25);
    expect(repository.reporterConfigured, isTrue);
  });

  test('apply sets the switch and moves the moment of consent', () async {
    final runtime = _runtime();
    final repository = CrashReportsRepositoryImpl(runtime: runtime, configured: false);
    final since = DateTime.utc(2026, 11, 22, 12);

    await repository.apply(enabled: true, since: since);

    expect(runtime.toggle.enabled, isTrue);
    expect(runtime.outbox.consentSince, since);
    expect(repository.reporterConfigured, isFalse);
    await runtime.sender.stop();
  });

  test('without a log database nothing is recorded and the build is not configured', () async {
    final repository = CrashReportsRepositoryImpl(runtime: null, configured: true);

    expect(await repository.recent(), isEmpty);
    expect(await repository.recorded(), 0);
    expect(repository.reporterConfigured, isFalse);
    await repository.apply(enabled: true, since: DateTime.utc(2026));
  });

  test('saveArchive writes app.log, outbox.json and meta.json with secrets cleaned', () async {
    final runtime = _runtime();
    runtime.buffer.add(
      LogMessage.verbose(
        message: 'key $_secret leaked',
        level: const LogLevel.info(),
        timestamp: DateTime.utc(2026, 11, 22),
      ),
    );
    await runtime.outbox.add(
      error: StateError('failed with $_secret'),
      stack: StackTrace.fromString('#0 f (package:flutter_code_agent/a.dart:1:1)'),
      level: 'error',
      breadcrumbs: const <String>[],
    );
    final path = '${dir.path}/log.zip';

    await CrashReportsRepositoryImpl(runtime: runtime, configured: true).saveArchive(path);

    final files = _unzip(path);
    expect(files.keys, containsAll(<String>['app.log', 'outbox.json', 'meta.json']));
    expect(files['app.log'], contains('[REDACTED]'));
    for (final text in files.values) {
      expect(text, isNot(contains(_secret)));
    }
    expect(jsonDecode(files['outbox.json']!), hasLength(1));
    expect(jsonDecode(files['meta.json']!), containsPair('version', '1.0.0'));
  });

  test('saveArchive without a log database writes log-unavailable.txt and meta.json', () async {
    final path = '${dir.path}/log.zip';

    await CrashReportsRepositoryImpl(runtime: null, configured: false).saveArchive(path);

    final files = _unzip(path);
    expect(files.keys, unorderedEquals(<String>['log-unavailable.txt', 'meta.json']));
  });
}
