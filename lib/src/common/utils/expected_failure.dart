import 'dart:async';
import 'dart:io';

import 'package:flutter_code_agent/src/common/acp/agent_hub_types.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/dart_analysis_server.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/lsp_connection.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/emulator_launcher.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_exceptions.dart';
import 'package:flutter_code_agent/src/common/utils/expected_exception.dart';

/// The packages of this app: their stack frames count as the app's own in the fingerprint and in
/// Sentry.
const Set<String> fagentPackages = <String>{'flutter_code_agent'};

/// Whether [error] is expected: the user or the outside world caused it and the UI shows it. It is
/// written to the log, but not queued for crash reports. The one place that decides.
///
/// Expected: every [ExpectedException], a [TimeoutException], a [SocketException], and the ends of
/// the child processes the app talks to (the Flutter daemon or the Dart language server exited or
/// was closed, an analysis start was cancelled, an agent was removed, an emulator would not start).
bool isExpectedFailure(Object error) =>
    error is ExpectedException ||
    error is TimeoutException ||
    error is SocketException ||
    error is DaemonClosedException ||
    error is LspClosedException ||
    error is DartAnalysisStartCancelled ||
    error is AgentRemovedException ||
    error is EmulatorLaunchException;
