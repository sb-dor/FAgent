import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show LazyDatabase, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_code_agent/src/common/telemetry/clip.dart';
import 'package:flutter_code_agent/src/common/telemetry/log_buffer.dart';
import 'package:flutter_code_agent/src/common/telemetry/log_storage.dart';
import 'package:flutter_code_agent/src/common/telemetry/telemetry_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l/l.dart';

LogMessage _m(int i, {StackTrace? stack, String? text}) =>
    LogMessage.create(text ?? 'm$i', const LogLevel.warning(), stackTrace: stack);

TelemetryDatabase _db() => TelemetryDatabase.forTesting(NativeDatabase.memory());

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
    'trimStoredLogs keeps the newest `keep` by id, readStoredLogs returns them oldest first',
    () async {
      final db = _db();
      addTearDown(db.close);
      await db.batch(
        (b) => b.insertAll(db.logEntries, [
          for (var i = 0; i < 10; i++)
            LogEntriesCompanion.insert(
              time: DateTime.utc(2026, 11, 12, 0, 0, i).millisecondsSinceEpoch,
              level: const LogLevel.info().level,
              message: 'm$i',
            ),
        ]),
      );
      await trimStoredLogs(db, keep: 4);
      final all = await readStoredLogs(db);
      expect(all.map((m) => m.message), ['m6', 'm7', 'm8', 'm9']);
      expect(all.first.timestamp.isUtc, isTrue);
      expect(all.first.timestamp, DateTime.utc(2026, 11, 12, 0, 0, 6));
      final two = await readStoredLogs(db, limit: 2);
      expect(two.map((m) => m.message), ['m8', 'm9']);
    },
  );

  test('readStoredLogs returns a stack as LogMessageError', () async {
    final db = _db();
    addTearDown(db.close);
    await db
        .into(db.logEntries)
        .insert(
          LogEntriesCompanion.insert(
            time: 0,
            level: const LogLevel.error().level,
            message: 'boom',
            stack: const Value('#0 main'),
          ),
        );
    final m = (await readStoredLogs(db)).single;
    expect(m, isA<LogMessageError>());
    expect((m as LogMessageError).stackTrace.toString(), '#0 main');
  });

  test('attachLogStorage writes a batch after 5 seconds; to the buffer at once', () {
    fakeAsync((async) {
      final db = _db();
      final buffer = LogBuffer();
      final controller = StreamController<LogMessage>.broadcast(sync: true);
      final sub = attachLogStorage(logs: controller.stream, db: db, buffer: buffer);

      controller
        ..add(_m(1))
        ..add(_m(2, text: 'Bearer secret-token'));
      expect(buffer.logs, hasLength(2));

      List<LogMessage>? stored;
      async.elapse(const Duration(seconds: 4));
      readStoredLogs(db).then((v) => stored = v);
      async.flushMicrotasks();
      expect(stored, isEmpty);

      async
        ..elapse(const Duration(seconds: 1))
        ..flushMicrotasks();
      readStoredLogs(db).then((v) => stored = v);
      async.flushMicrotasks();
      expect(stored!.map((m) => m.message), ['m1', 'Bearer [REDACTED]']);

      sub.cancel();
      controller.close();
      db.close();
      async.flushMicrotasks();
    });
  });

  test('attachLogStorage: a database failure is not thrown, the buffer keeps working', () {
    final errors = <Object>[];
    runZonedGuarded(() {
      fakeAsync((async) {
        final db = TelemetryDatabase.forTesting(
          LazyDatabase(() async => throw StateError('disk full')),
        );
        final buffer = LogBuffer();
        final controller = StreamController<LogMessage>.broadcast(sync: true);
        attachLogStorage(logs: controller.stream, db: db, buffer: buffer);

        controller.add(_m(1));
        async
          ..elapse(const Duration(seconds: 6))
          ..flushMicrotasks();
        controller.add(_m(2));
        expect(buffer.logs, hasLength(2));
        async
          ..elapse(const Duration(seconds: 6))
          ..flushMicrotasks();
        controller.close();
      });
    }, (e, _) => errors.add(e));
    expect(errors, isEmpty);
  });

  test('flushAndClose writes the batch at once and cancels the timer', () async {
    final db = _db();
    addTearDown(db.close);
    final controller = StreamController<LogMessage>.broadcast(sync: true);
    final storage = attachLogStorage(logs: controller.stream, db: db, buffer: LogBuffer());
    controller.add(_m(1));
    await storage.flushAndClose();
    expect((await readStoredLogs(db)).map((m) => m.message), ['m1']);
    controller.add(_m(2));
    await Future<void>.delayed(Duration.zero);
    expect(await readStoredLogs(db), hasLength(1));
    await controller.close();
  });

  test('a log stream error does not reach the zone and does not break the subscription', () async {
    final errors = <Object>[];
    await runZonedGuarded(() async {
      final db = _db();
      addTearDown(db.close);
      final controller = StreamController<LogMessage>.broadcast(sync: true);
      final buffer = LogBuffer();
      final storage = attachLogStorage(logs: controller.stream, db: db, buffer: buffer);
      controller
        ..addError(StateError('stream failure'))
        ..add(_m(1));
      await Future<void>.delayed(Duration.zero);
      expect(buffer.logs, hasLength(1));
      await storage.flushAndClose();
      await controller.close();
    }, (e, _) => errors.add(e));
    expect(errors, isEmpty);
  });

  test('a huge message and stack are limited in the database', () async {
    final db = _db();
    addTearDown(db.close);
    final controller = StreamController<LogMessage>.broadcast(sync: true);
    final storage = attachLogStorage(logs: controller.stream, db: db, buffer: LogBuffer());
    controller.add(_m(1, text: 'z' * 200000, stack: StackTrace.fromString('s' * 200000)));
    await storage.flushAndClose();
    final row = await db.select(db.logEntries).getSingle();
    expect(row.message.length, lessThanOrEqualTo(logClipLength + 1));
    expect(row.stack!.length, lessThanOrEqualTo(logClipLength + 1));
    await controller.close();
  });

  test('the log database file gives space back after trimming (auto_vacuum incremental)', () async {
    final dir = Directory.systemTemp.createTempSync('telemetry_logs_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/logs.sqlite');
    final fileDb = openTelemetryDatabase(file);
    addTearDown(fileDb.close);
    final text = 'z' * 4000;
    for (var i = 0; i < 400; i++) {
      await fileDb.customStatement(
        'INSERT INTO log_entries (time, level, message) VALUES (?, 1, ?)',
        [i, text],
      );
    }
    await fileDb.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    final before = file.lengthSync();

    await trimStoredLogs(fileDb, keep: 10);
    await fileDb.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');

    expect(before, greaterThan(1000000));
    expect(file.lengthSync(), lessThan(before ~/ 4));
  });
}
