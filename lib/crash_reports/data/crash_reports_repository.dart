import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:clock/clock.dart';
import 'package:flutter_code_agent/_core/telemetry/telemetry.dart';

/// How many recent errors Settings shows.
const int recentErrorsLimit = 20;

/// The error log and the sending of errors, as Settings sees them.
abstract interface class ICrashReportsRepository {
  /// The state of the sender now.
  TelemetryStatus get status;

  /// Changes of the sender's state.
  Stream<TelemetryStatus> get statusChanges;

  /// Whether this build has a reporter configured (a DSN); without one nothing is sent.
  bool get reporterConfigured;

  /// The last [recentErrorsLimit] errors of the queue, newest first.
  Future<List<OutboxEntry>> recent();

  /// How many errors the queue holds, sent or not.
  Future<int> recorded();

  /// Applies the user's switch. A non-null [since] is the moment of consent.
  Future<void> apply({required bool enabled, DateTime? since});

  /// Writes a zip of the log, the queue and the build details, cleaned of secrets, to [path].
  Future<void> saveArchive(String path);
}

/// [ICrashReportsRepository] over the [TelemetryRuntime].
///
/// [runtime] is `null` when `logs.sqlite` could not be opened: nothing is shown and the archive
/// says so.
final class CrashReportsRepositoryImpl implements ICrashReportsRepository {
  /// Creates the repository.
  CrashReportsRepositoryImpl({required this._runtime, required this._configured});

  final TelemetryRuntime? _runtime;
  final bool _configured;

  @override
  TelemetryStatus get status => _runtime?.sender.current ?? TelemetryStatus.initial;

  @override
  Stream<TelemetryStatus> get statusChanges =>
      _runtime?.sender.status ?? const Stream<TelemetryStatus>.empty();

  @override
  bool get reporterConfigured => _configured && _runtime != null;

  @override
  Future<List<OutboxEntry>> recent() async =>
      await _runtime?.outbox.recent(recentErrorsLimit) ?? const <OutboxEntry>[];

  @override
  Future<int> recorded() async => await _runtime?.outbox.length() ?? 0;

  @override
  Future<void> apply({required bool enabled, DateTime? since}) async =>
      _runtime?.setEnabled(enabled, since: since);

  @override
  Future<void> saveArchive(String path) async {
    final runtime = _runtime;
    final meta = <String, Object?>{
      'app': 'flutter_code_agent',
      'version': runtime?.outbox.appVersion,
      'platform': Platform.operatingSystem,
      'generatedAt': clock.now().toUtc().toIso8601String(),
      'crashReportsEnabled': runtime?.toggle.enabled ?? false,
    };
    final Map<String, String> files;
    List<RawLogLine>? log;
    if (runtime == null) {
      files = <String, String>{
        'log-unavailable.txt': 'The log is unavailable: logs.sqlite could not be opened.',
        'meta.json': jsonEncode(meta),
      };
    } else {
      final queue = await runtime.outbox.oldest(runtime.outbox.capacity);
      meta['recorded'] = queue.length;
      files = <String, String>{
        'outbox.json': jsonEncode(<Object?>[for (final entry in queue) _entryJson(entry)]),
        'meta.json': jsonEncode(meta),
      };
      log = runtime.buffer.rawLines(LogBuffer.limit);
    }
    // Cleaning and zipping a large log happen off the main isolate: the window does not freeze.
    final zip = await Isolate.run(() => _buildArchive(files, log));
    await File(path).writeAsBytes(zip);
  }

  Map<String, Object?> _entryJson(OutboxEntry e) => <String, Object?>{
    'fingerprint': e.fingerprint,
    'firstAt': e.firstAt.toIso8601String(),
    'lastAt': e.lastAt.toIso8601String(),
    'count': e.count,
    'attempts': e.attempts,
    'level': e.level,
    'type': e.type,
    'message': e.message,
    'stack': e.stack,
    'hint': e.hint,
    'breadcrumbs': e.breadcrumbs,
    'appVersion': e.appVersion,
    'platform': e.platform,
  };
}

// A top-level function, not a closure in the method: a closure would carry `this` (the log
// database), which cannot go to another isolate.
List<int> _buildArchive(Map<String, String> files, List<RawLogLine>? log) {
  final archive = Archive();
  void addText(String name, String text) =>
      archive.addFile(ArchiveFile.bytes(name, utf8.encode(redactSecrets(text))));
  files.forEach(addText);
  if (log != null) addText('app.log', formatRawLogLines(log));
  return ZipEncoder().encode(archive);
}
