import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import 'package:flutter_code_agent/src/common/telemetry/fingerprint.dart';
import 'package:flutter_code_agent/src/common/telemetry/redact.dart';
import 'package:flutter_code_agent/src/common/telemetry/telemetry_database.dart';

/// An error that names its own type: this is how an error with hidden details (a wrapper instead
/// of the original exception) goes to the queue and Sentry under the original type.
abstract interface class ReportedError {
  /// The type of the original error.
  String get reportedType;
}

/// The error type for the queue and the fingerprint: [ReportedError.reportedType] or `runtimeType`.
String errorTypeName(Object error) =>
    error is ReportedError ? error.reportedType : error.runtimeType.toString();

/// An entry of the error queue, the text already cleaned of secrets.
final class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.fingerprint,
    required this.firstAt,
    required this.lastAt,
    required this.count,
    required this.attempts,
    required this.level,
    required this.type,
    required this.message,
    required this.stack,
    required this.hint,
    required this.breadcrumbs,
    required this.appVersion,
    required this.platform,
  });

  final int id;
  final String fingerprint;
  final DateTime firstAt;
  final DateTime lastAt;

  /// How many times the error repeated.
  final int count;

  /// How many times Sentry did not accept the entry while the connection was available.
  final int attempts;

  /// The Sentry level: `error`, `fatal`, `warning`.
  final String level;
  final String type;
  final String message;
  final String stack;
  final String? hint;
  final List<String> breadcrumbs;
  final String appVersion;
  final String platform;
}

/// The queue of errors to send: secrets cleaned, merged by fingerprint, at most [capacity].
final class ErrorOutbox {
  ErrorOutbox(
    this._db, {
    required this.appVersion,
    required this.platform,
    required this.projectPackages,
    this.capacity = 200,
    this.consentSince,
  });

  final TelemetryDatabase _db;
  final String appVersion;
  final String platform;

  /// The names of the project's packages: whose stack frames make up the fingerprint.
  final Set<String> projectPackages;

  /// How many entries are kept; on overflow the oldest by `lastAt` goes.
  final int capacity;

  /// The moment the user turned crash reports on. Only entries whose first occurrence is at or
  /// after it may be sent ([sendable]); earlier ones stay on the machine. `null`: no switch, every
  /// entry may be sent.
  DateTime? consentSince;

  /// Called after the queue changes (the sender updates its counter from it).
  void Function()? onChanged;

  /// Puts an error into the queue. The same one (by [errorFingerprint]) increases `count` and
  /// `lastAt`.
  Future<void> add({
    required Object error,
    required StackTrace stack,
    String? hint,
    required String level,
    required List<String> breadcrumbs,
    DateTime? at,
  }) async {
    final fingerprint = errorFingerprint(error, stack, projectPackages: projectPackages);
    final crumbs = _afterConsent(breadcrumbs);
    final now = (at ?? clock.now()).toUtc().millisecondsSinceEpoch;
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.errorOutboxEntries,
      )..where((t) => t.fingerprint.equals(fingerprint))).getSingleOrNull();
      if (existing != null) {
        final since = consentSince?.toUtc().millisecondsSinceEpoch;
        if (since != null && existing.firstAt < since) {
          // The stored occurrence predates consent: its data must never leave the machine, so the
          // row now describes only this new occurrence.
          await (_db.update(_db.errorOutboxEntries)..where((t) => t.id.equals(existing.id))).write(
            ErrorOutboxEntriesCompanion(
              firstAt: Value(now),
              lastAt: Value(now),
              count: const Value(1),
              attempts: const Value(0),
              level: Value(level),
              type: Value(errorTypeName(error)),
              message: Value(cleanForLog(error.toString())),
              stack: Value(cleanForLog(stack.toString())),
              hint: Value(hint == null ? null : cleanForLog(hint)),
              breadcrumbs: Value(jsonEncode([for (final b in crumbs) cleanForLog(b)])),
              appVersion: Value(appVersion),
              platform: Value(platform),
            ),
          );
          return;
        }
        await (_db.update(_db.errorOutboxEntries)..where((t) => t.id.equals(existing.id))).write(
          ErrorOutboxEntriesCompanion(count: Value(existing.count + 1), lastAt: Value(now)),
        );
        return;
      }
      await _db
          .into(_db.errorOutboxEntries)
          .insert(
            ErrorOutboxEntriesCompanion.insert(
              fingerprint: fingerprint,
              firstAt: now,
              lastAt: now,
              level: level,
              type: errorTypeName(error),
              message: cleanForLog(error.toString()),
              stack: cleanForLog(stack.toString()),
              hint: Value(hint == null ? null : cleanForLog(hint)),
              breadcrumbs: jsonEncode([for (final b in crumbs) cleanForLog(b)]),
              appVersion: appVersion,
              platform: platform,
            ),
          );
      // Ordered by last_at, then id: when the clock is set back, the "oldest" can be newer by id
      // but is evicted by its write time, as agreed.
      await _db.customStatement(
        'DELETE FROM error_outbox_entries WHERE id IN '
        '(SELECT id FROM error_outbox_entries ORDER BY last_at ASC, id ASC '
        'LIMIT MAX(0, (SELECT COUNT(*) FROM error_outbox_entries) - ?))',
        [capacity],
      );
    });
    onChanged?.call();
  }

  /// The breadcrumb lines written at or after [consentSince]: a line starts with its ISO time
  /// (`2026-11-12T10:15:03.120Z [E] …`); one whose time does not parse is dropped too. All lines
  /// when there is no consent time.
  List<String> _afterConsent(List<String> lines) {
    final since = consentSince;
    if (since == null) {
      return lines;
    }
    return [
      for (final line in lines)
        if (_lineTime(line) case final time? when !time.isBefore(since)) line,
    ];
  }

  static DateTime? _lineTime(String line) {
    final end = line.indexOf(' ');
    return DateTime.tryParse(end < 0 ? line : line.substring(0, end));
  }

  /// Up to [n] oldest entries, by time of the first occurrence.
  Future<List<OutboxEntry>> oldest(int n) async {
    final rows =
        await (_db.select(_db.errorOutboxEntries)
              ..orderBy([(t) => OrderingTerm.asc(t.firstAt), (t) => OrderingTerm.asc(t.id)])
              ..limit(n))
            .get();
    return [for (final row in rows) _entry(row)];
  }

  /// Up to [n] newest entries by time of the first occurrence, from oldest to newest.
  Future<List<OutboxEntry>> newest(int n) async {
    final rows =
        await (_db.select(_db.errorOutboxEntries)
              ..orderBy([(t) => OrderingTerm.desc(t.firstAt), (t) => OrderingTerm.desc(t.id)])
              ..limit(n))
            .get();
    return [for (final row in rows.reversed) _entry(row)];
  }

  /// Up to [n] entries that may be sent: those first seen at or after [consentSince] (all when it
  /// is `null`). The oldest ones, or with [newestFirst] the newest ones, from oldest to newest.
  Future<List<OutboxEntry>> sendable(int n, {required bool newestFirst}) async {
    final since = consentSince?.toUtc().millisecondsSinceEpoch;
    final query = _db.select(_db.errorOutboxEntries);
    if (since != null) {
      query.where((t) => t.firstAt.isBiggerOrEqualValue(since));
    }
    final order = newestFirst ? OrderingTerm.desc : OrderingTerm.asc;
    query
      ..orderBy([(t) => order(t.firstAt), (t) => order(t.id)])
      ..limit(n);
    final rows = await query.get();
    return [for (final row in newestFirst ? rows.reversed : rows) _entry(row)];
  }

  /// Up to [n] latest entries by time of the last occurrence, newest first.
  Future<List<OutboxEntry>> recent(int n) async {
    final rows =
        await (_db.select(_db.errorOutboxEntries)
              ..orderBy([(t) => OrderingTerm.desc(t.lastAt), (t) => OrderingTerm.desc(t.id)])
              ..limit(n))
            .get();
    return [for (final row in rows) _entry(row)];
  }

  Future<void> remove(int id) async {
    await (_db.delete(_db.errorOutboxEntries)..where((t) => t.id.equals(id))).go();
    onChanged?.call();
  }

  /// Marks a failed attempt to send.
  Future<void> markAttempt(int id) async {
    await _db.customStatement(
      'UPDATE error_outbox_entries SET attempts = attempts + 1 WHERE id = ?',
      [id],
    );
  }

  /// Empties the queue.
  Future<void> clear() async {
    await _db.delete(_db.errorOutboxEntries).go();
    onChanged?.call();
  }

  Future<int> length() async {
    final count = _db.errorOutboxEntries.id.count();
    final query = _db.selectOnly(_db.errorOutboxEntries)..addColumns([count]);
    return await query.map((r) => r.read(count)).getSingle() ?? 0;
  }

  OutboxEntry _entry(ErrorOutboxEntry row) {
    return OutboxEntry(
      id: row.id,
      fingerprint: row.fingerprint,
      firstAt: DateTime.fromMillisecondsSinceEpoch(row.firstAt, isUtc: true),
      lastAt: DateTime.fromMillisecondsSinceEpoch(row.lastAt, isUtc: true),
      count: row.count,
      attempts: row.attempts,
      level: row.level,
      type: row.type,
      message: row.message,
      stack: row.stack,
      hint: row.hint,
      breadcrumbs: [for (final b in jsonDecode(row.breadcrumbs) as List<dynamic>) b as String],
      appVersion: row.appVersion,
      platform: row.platform,
    );
  }
}
