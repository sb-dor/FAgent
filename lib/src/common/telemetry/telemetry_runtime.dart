import 'dart:async';

import 'package:flutter_code_agent/src/common/telemetry/crash_report_gateway.dart';
import 'package:flutter_code_agent/src/common/telemetry/error_outbox.dart';
import 'package:flutter_code_agent/src/common/telemetry/error_reporter.dart';
import 'package:flutter_code_agent/src/common/telemetry/log_buffer.dart';
import 'package:flutter_code_agent/src/common/telemetry/log_storage.dart';
import 'package:flutter_code_agent/src/common/telemetry/telemetry_database.dart';
import 'package:flutter_code_agent/src/common/telemetry/telemetry_sender.dart';

/// Whether sending errors is on: the user's switch.
final class TelemetryToggle {
  /// Creates the toggle. Apps start with it off until the setting is read.
  TelemetryToggle({this.enabled = false});

  /// Sending is on.
  bool enabled;
}

/// The log, the error queue and the sender of the app.
final class TelemetryRuntime {
  /// Builds the queue, the `ErrorReporter` core and the sender over the log database [db].
  ///
  /// [isExpected] decides that an error is expected and stays out of the queue. [projectPackages]
  /// are the packages of the project: they tell the fingerprint which frames are its own. The
  /// sender works only when [enabled] (the user's switch) and [reporterConfigured]: without a
  /// configured reporter nothing is sent.
  TelemetryRuntime({
    required this.db,
    required ICrashReportGateway gateway,
    required String appVersion,
    required String platform,
    required bool Function(Object error) isExpected,
    required Set<String> projectPackages,
    bool enabled = false,
    DateTime? consentSince,
    this.reporterConfigured = true,
    this.releaseGateway,
    LogBuffer? buffer,
  }) : toggle = TelemetryToggle(enabled: enabled),
       buffer = buffer ?? LogBuffer(),
       outbox = ErrorOutbox(
         db,
         appVersion: appVersion,
         platform: platform,
         projectPackages: projectPackages,
         consentSince: consentSince,
       ) {
    reporter = ErrorReporter(outbox: outbox, buffer: this.buffer, isExpected: isExpected);
    sender = TelemetrySender(
      outbox: outbox,
      gateway: gateway,
      enabled: () => toggle.enabled && reporterConfigured,
    );
  }

  /// The `logs.sqlite` database.
  final TelemetryDatabase db;

  /// Whether the build has a reporter configured (a DSN).
  final bool reporterConfigured;

  /// Closes the gateway when sending was turned off.
  final Future<void> Function()? releaseGateway;

  /// Whether sending is on.
  final TelemetryToggle toggle;

  /// The last log records in memory.
  final LogBuffer buffer;

  /// The queue of errors to send.
  final ErrorOutbox outbox;

  /// The shared core of `ErrorUtil`.
  late final ErrorReporter reporter;

  /// The sender of the queue.
  late final TelemetrySender sender;

  /// The log writer to the database; set at start.
  LogStorage? storage;

  /// Applies the user's switch: turning on runs an extra pass, turning off stops the sender and
  /// closes the gateway. Repeating the same value does nothing.
  ///
  /// [since] is the moment of consent: only errors first seen at or after it are sent. It is set
  /// before the pass that turning on starts.
  Future<void> setEnabled(bool enabled, {DateTime? since}) {
    // Calls go in turn: a quick "off, on" will not close the gateway after the turn on.
    final next = _setting.then((_) => _apply(enabled, since));
    _setting = next.catchError((Object _) {});
    return next;
  }

  Future<void> _setting = Future<void>.value();

  Future<void> _apply(bool enabled, DateTime? since) async {
    if (since != null) {
      outbox.consentSince = since;
    }
    final was = toggle.enabled;
    toggle.enabled = enabled;
    if (enabled && !was) {
      // `start` sets the timer again (turning off stopped it) and runs a pass at once.
      sender.start();
    } else if (!enabled && was) {
      // A running pass is finished before the gateway is closed.
      await sender.stop();
      try {
        await releaseGateway?.call();
      } on Object {
        // Not closed: the gateway closes on exit, nothing to lose.
      }
    }
  }

  /// Waits until the started error records and queue counter refreshes are written: before the log
  /// database is closed.
  Future<void> settled() async {
    await reporter.settled();
    await sender.settled();
  }

  /// Erases the queue and the log in memory and on disk: the data of a former device or former
  /// settings must not go to a new one.
  Future<void> resetData() async {
    // Started records are finished before the reset, or they would appear in the queue after it.
    await settled();
    await outbox.clear();
    buffer.clear();
    await storage?.clear();
  }
}
