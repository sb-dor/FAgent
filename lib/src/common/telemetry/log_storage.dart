import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/telemetry/log_buffer.dart';
import 'package:flutter_code_agent/src/common/telemetry/redact.dart';
import 'package:flutter_code_agent/src/common/telemetry/telemetry_database.dart';
import 'package:l/l.dart';

/// How often the accumulated records are written to the database.
const Duration logFlushInterval = Duration(seconds: 5);

/// Keeps the last [keep] log records in the database.
Future<void> trimStoredLogs(TelemetryDatabase db, {int keep = LogBuffer.limit}) async {
  await db.customStatement(
    'DELETE FROM log_entries WHERE id <= (SELECT MAX(id) FROM log_entries) - ?',
    [keep],
  );
  // The freed pages go back to the file system (in a file without `auto_vacuum` the command does
  // nothing).
  await db.customStatement('PRAGMA incremental_vacuum');
}

/// Up to [limit] last records from the database, from oldest to newest.
Future<List<LogMessage>> readStoredLogs(TelemetryDatabase db, {int limit = LogBuffer.limit}) async {
  final rows =
      await (db.select(db.logEntries)
            ..orderBy([(t) => OrderingTerm.desc(t.id)])
            ..limit(limit))
          .get();
  return [for (final row in rows.reversed) _toMessage(row)];
}

LogMessage _toMessage(LogEntry row) {
  final level = LogLevel.fromValue(row.level);
  final timestamp = DateTime.fromMillisecondsSinceEpoch(row.time, isUtc: true);
  final stack = row.stack;
  if (stack == null) {
    return LogMessageVerbose(message: row.message, level: level, timestamp: timestamp);
  }
  return LogMessageError(
    message: row.message,
    level: level,
    timestamp: timestamp,
    stackTrace: StackTrace.fromString(stack),
  );
}

/// Writes the log to the database in batches. Obtained from [attachLogStorage].
final class LogStorage {
  LogStorage._(this._db, this._buffer);

  final TelemetryDatabase _db;
  final LogBuffer _buffer;
  late final StreamSubscription<LogMessage> _subscription;
  List<LogMessage> _pending = <LogMessage>[];
  Timer? _timer;
  Future<void> _inflight = Future<void>.value();

  void _add(LogMessage message) {
    _buffer.add(message);
    _pending.add(message);
    _timer ??= Timer(logFlushInterval, () => unawaited(_flush()));
  }

  /// Unsubscribes from the stream. The accumulated batch is written by the timer; to write it at
  /// once and cancel the timer, use [flushAndClose].
  Future<void> cancel() => _subscription.cancel();

  /// Unsubscribes, cancels the timer and writes what is accumulated to the database. Does not throw.
  Future<void> flushAndClose() async {
    await _subscription.cancel();
    _timer?.cancel();
    await _flush();
  }

  /// Drops the batch not yet written and erases the log on disk.
  Future<void> clear() async {
    _timer?.cancel();
    _timer = null;
    _pending = <LogMessage>[];
    _inflight = _inflight.then((_) async {
      try {
        await _db.delete(_db.logEntries).go();
      } on Object catch (error) {
        _report('Log: could not clear: $error');
      }
    });
    await _inflight;
  }

  Future<void> _flush() => _inflight = _inflight.then((_) => _write());

  Future<void> _write() async {
    _timer = null;
    final batch = _pending;
    _pending = <LogMessage>[];
    if (batch.isEmpty) {
      return;
    }
    try {
      await _db.batch(
        (b) => b.insertAll(_db.logEntries, [
          for (final m in batch)
            LogEntriesCompanion.insert(
              time: m.timestamp.toUtc().millisecondsSinceEpoch,
              level: m.level.level,
              message: cleanForLog(m.message.toString()),
              stack: Value(_stackOf(m)),
            ),
        ]),
      );
      await trimStoredLogs(_db);
    } on Object catch (error) {
      _report('Log: could not write ${batch.length} records: $error');
    }
  }
}

/// Subscribes [buffer] and [db] to [logs]: a record goes to the buffer at once and to the database
/// in a batch once per [logFlushInterval]. A write failure and a stream error are not thrown: one
/// line to `stderr`, without `ErrorUtil`, so that the log does not call itself.
LogStorage attachLogStorage({
  required Stream<LogMessage> logs,
  required TelemetryDatabase db,
  required LogBuffer buffer,
}) {
  final storage = LogStorage._(db, buffer);
  storage._subscription = logs.listen(
    storage._add,
    onError: (Object error, StackTrace _) => _report('Log: stream error: $error'),
  );
  return storage;
}

void _report(String text) {
  try {
    stderr.writeln(text);
  } on Object {
    // stderr is unavailable: nothing to lose.
  }
}

String? _stackOf(LogMessage m) {
  if (m is! LogMessageError) {
    return null;
  }
  final text = m.stackTrace.toString();
  return text.isEmpty ? null : cleanForLog(text);
}
