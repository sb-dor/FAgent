import 'dart:async';
import 'dart:io';

import 'package:flutter_code_agent/src/common/constant/config.dart';
import 'package:flutter_code_agent/src/common/telemetry/telemetry.dart';
import 'package:flutter_code_agent/src/common/utils/error_util.dart';
import 'package:flutter_code_agent/src/common/utils/expected_failure.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:path_provider/path_provider.dart';

/// The first startup step: opens `logs.sqlite` in the application support directory and connects
/// the log, the queue and the sender to [ErrorUtil].
///
/// When the log cannot be opened, [Dependencies.telemetryRuntime] stays `null`: the app works
/// without the log on disk, errors go to the console, and the steps after this one still run.
/// Sending starts off (the user's switch, with the moment of consent, is wired by the settings).
/// Closing is [Dependencies.closeErrorLog].
Future<void> startErrorLog(
  Dependencies dependencies, {
  Future<Directory> Function() supportDirectory = getApplicationSupportDirectory,
}) async {
  final gateway = SentryGateway(
    dsn: Config.sentryDsn,
    projectPackages: fagentPackages,
    release: Config.appVersion,
  );
  dependencies
    ..sentryGateway = gateway
    ..telemetryRuntime = await startTelemetry(
      supportDirectory: supportDirectory,
      hub: ErrorUtil.hub,
      gateway: gateway,
      reporterConfigured: gateway.enabled,
      appVersion: Config.appVersion,
      isExpected: isExpectedFailure,
      projectPackages: fagentPackages,
      releaseGateway: gateway.close,
      defer: (name, step) => dependencies.errorLogClosers.add(step),
    );
  // After the log: closing the log may still report.
  dependencies.errorLogClosers.add(gateway.close);
}
