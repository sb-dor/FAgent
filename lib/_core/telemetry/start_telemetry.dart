import 'dart:async';
import 'dart:io';

import 'package:flutter_code_agent/_core/telemetry/crash_report_gateway.dart';
import 'package:flutter_code_agent/_core/telemetry/error_hub.dart';
import 'package:flutter_code_agent/_core/telemetry/log_storage.dart';
import 'package:flutter_code_agent/_core/telemetry/telemetry_database.dart';
import 'package:flutter_code_agent/_core/telemetry/telemetry_runtime.dart';
import 'package:l/l.dart';
import 'package:path/path.dart' as p;

/// Opens `logs.sqlite` in [supportDirectory], connects the log, the queue and the sender to [hub].
///
/// If the database cannot be opened (disk full, file busy or damaged), returns `null`: the app
/// works without the log on disk, [hub] writes to the console. Closing the resources is passed to
/// [defer] (the app's shutdown step). Sending starts with [enabled]; apps turn it on once the
/// user's setting is read. [consentSince] is when the user turned crash reports on: nothing recorded
/// before it is sent (`null`: no switch, everything may be sent). [projectPackages] are the
/// packages of the project (fingerprint frames). [hideDetails] is `ErrorReporter.hideDetails`
/// (none by default: the full text goes out after `redactSecrets`).
Future<TelemetryRuntime?> startTelemetry({
  required Future<Directory> Function() supportDirectory,
  required ErrorHub hub,
  required ICrashReportGateway gateway,
  required bool reporterConfigured,
  required String appVersion,
  required bool Function(Object error) isExpected,
  required Set<String> projectPackages,
  required void Function(String name, Future<void> Function() step) defer,
  Future<void> Function()? releaseGateway,
  Object Function(Object error)? hideDetails,
  String? platform,
  bool enabled = false,
  DateTime? consentSince,
}) async {
  TelemetryDatabase? db;
  try {
    final dir = await supportDirectory();
    await dir.create(recursive: true);
    db = openTelemetryDatabase(File(p.join(dir.path, 'logs.sqlite')));
    // The database opens lazily: a read checks that the file is usable.
    final stored = await readStoredLogs(db);
    final runtime = TelemetryRuntime(
      db: db,
      gateway: gateway,
      platform: platform ?? Platform.operatingSystem,
      appVersion: appVersion,
      isExpected: isExpected,
      projectPackages: projectPackages,
      hideDetails: hideDetails,
      enabled: enabled,
      consentSince: consentSince,
      reporterConfigured: reporterConfigured,
      releaseGateway: releaseGateway,
    )..buffer.addAll(stored);
    final storage = runtime.storage = attachLogStorage(logs: l, db: db, buffer: runtime.buffer);
    hub.configure(runtime);
    defer('Close the error log', () async {
      await runtime.sender.stop();
      await hub.settled();
      // From now on errors pile up in memory until the next configure (a repeated start).
      hub.disconnect(runtime);
      await storage.flushAndClose();
      await runtime.sender.dispose();
      await db?.close();
    });
    runtime.sender.start();
    return runtime;
  } on Object catch (error) {
    try {
      hub.console('The error log is unavailable, the app works without it: $error');
      await db?.close();
    } on Object {
      // The console or the database is already unavailable: nothing to lose.
    }
    return null;
  }
}
