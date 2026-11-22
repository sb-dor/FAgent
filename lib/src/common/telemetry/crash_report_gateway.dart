import 'package:flutter_code_agent/src/common/telemetry/error_outbox.dart';

/// The link to a crash reporting service. The real implementation is given by the app, tests
/// substitute a fake.
abstract interface class ICrashReportGateway {
  /// Whether the service host answers, within a timeout; `false` on any failure or when no
  /// reporter is configured.
  Future<bool> reachable();

  /// Sends one entry; `true` when the service accepted it.
  Future<bool> send(OutboxEntry entry);
}
