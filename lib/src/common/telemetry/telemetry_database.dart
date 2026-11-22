import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'telemetry_database.g.dart';

/// The log: the last records, kept across restarts.
class LogEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Time, milliseconds since the epoch, UTC.
  IntColumn get time => integer()();

  /// `LogLevel.level` from the `l` package.
  IntColumn get level => integer()();

  TextColumn get message => text()();

  TextColumn get stack => text().nullable()();
}

/// The queue of errors waiting to be sent, merged by `fingerprint`.
class ErrorOutboxEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get fingerprint => text().unique()();

  /// Time of the first and the last occurrence, milliseconds since the epoch, UTC.
  IntColumn get firstAt => integer()();

  IntColumn get lastAt => integer()();

  IntColumn get count => integer().withDefault(const Constant(1))();

  /// How many times sending failed.
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// The Sentry level: `error`, `fatal`, `warning`.
  TextColumn get level => text()();

  TextColumn get type => text()();

  TextColumn get message => text()();

  TextColumn get stack => text()();

  TextColumn get hint => text().nullable()();

  /// The last log lines before the error.
  TextColumn get breadcrumbs => text()();

  TextColumn get appVersion => text()();

  TextColumn get platform => text()();
}

/// The `logs.sqlite` database: the log and the error queue. Its own schema, version 1.
@DriftDatabase(tables: [LogEntries, ErrorOutboxEntries])
class TelemetryDatabase extends _$TelemetryDatabase {
  TelemetryDatabase._(super.executor);

  /// The database on any executor, for tests.
  TelemetryDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;
}

/// Opens the database in [file] in a background isolate, WAL mode, `auto_vacuum = INCREMENTAL` for
/// a new file.
TelemetryDatabase openTelemetryDatabase(File file) {
  return TelemetryDatabase._(
    NativeDatabase.createInBackground(
      file,
      setup: (db) {
        // Before the tables are created: in a new file the space freed by trimming the log goes
        // back to the system.
        db
          ..execute('PRAGMA auto_vacuum = INCREMENTAL')
          ..execute('PRAGMA journal_mode = WAL');
      },
    ),
  );
}
