import 'package:flutter_code_agent/src/common/telemetry/telemetry.dart';
import 'package:flutter_code_agent/src/feature/crash_reports/data/crash_reports_repository.dart';

/// An [ICrashReportsRepository] with scripted data that records what it was asked to do.
final class FakeCrashReportsRepository implements ICrashReportsRepository {
  FakeCrashReportsRepository({
    this.entries = const <OutboxEntry>[],
    this.configured = true,
    this.saveError,
  });

  final List<OutboxEntry> entries;
  final bool configured;

  /// Thrown by [saveArchive] when set.
  final Exception? saveError;

  /// The paths [saveArchive] was called with.
  final List<String> saved = <String>[];

  /// The calls of [apply] as `(enabled, since)`.
  final List<(bool, DateTime?)> applied = <(bool, DateTime?)>[];

  @override
  TelemetryStatus get status => TelemetryStatus.initial;

  @override
  Stream<TelemetryStatus> get statusChanges => const Stream<TelemetryStatus>.empty();

  @override
  bool get reporterConfigured => configured;

  @override
  Future<List<OutboxEntry>> recent() async => entries.take(recentErrorsLimit).toList();

  @override
  Future<int> recorded() async => entries.length;

  @override
  Future<void> apply({required bool enabled, DateTime? since}) async =>
      applied.add((enabled, since));

  @override
  Future<void> saveArchive(String path) async {
    if (saveError case final error?) throw error;
    saved.add(path);
  }
}

/// An entry of the queue for tests.
OutboxEntry fakeOutboxEntry(int i, {int count = 1}) => OutboxEntry(
  id: i,
  fingerprint: 'fp$i',
  firstAt: DateTime.utc(2026, 11, 22, 10, i % 60),
  lastAt: DateTime.utc(2026, 11, 22, 11, i % 60),
  count: count,
  attempts: 0,
  level: 'error',
  type: 'StateError',
  message: 'boom $i',
  stack: '#0 main',
  hint: null,
  breadcrumbs: const <String>[],
  appVersion: '1.0.0',
  platform: 'test',
);
