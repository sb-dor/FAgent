import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_tool.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:path/path.dart' as p;

/// The most log lines `app_logs` returns.
const int appLogsMaxLines = 1000;

/// How many log lines `app_logs` returns when the agent does not say.
const int appLogsDefaultLines = 200;

/// How many errors `runtime_errors` returns (the newest).
const int runtimeErrorsLimit = 10;

const AppMcpError _notRunning = AppMcpError('App is not running');

/// The run of the caller's project while it is up, else the error to give the agent. A tool never
/// looks at another project's run.
RunRunning? _running(IAppRunRepository runs, AppMcpCaller caller) =>
    switch (runs.currentRun(caller.projectId)) {
      final RunRunning running => running,
      _ => null,
    };

/// `app_status`: the run of the chat's project.
final class AppStatusTool implements AppMcpTool {
  /// Creates the tool.
  const AppStatusTool({required this._runs});

  final IAppRunRepository _runs;

  @override
  String get name => 'app_status';

  @override
  String get description =>
      'Reports the app run of this chat\'s project: its state, device, build mode and the VM '
      'service, DTD and DevTools URIs. Pass the DTD URI to the dtd tool of the Dart MCP server '
      '(command connect) to inspect the running app.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{},
  };

  @override
  Future<AppMcpResult> call(AppMcpCaller caller, Map<String, Object?> arguments) async {
    final Map<String, Object?> status;
    switch (_runs.currentRun(caller.projectId)) {
      case RunIdle() || RunStopped():
        return const AppMcpText('No app is running');
      case RunBuilding(:final progress, :final label):
        status = {'state': 'building', 'label': ?label, 'progress': ?progress};
      case RunRunning(
        :final device,
        :final mode,
        :final vmServiceUri,
        :final dtdUri,
        :final devToolsUri,
        :final startedAt,
        :final lastReload,
      ):
        status = {
          'state': 'running',
          'device': device.name,
          'deviceId': device.id,
          'mode': mode.name,
          'vmServiceUri': vmServiceUri?.toString(),
          'dtdUri': dtdUri?.toString(),
          'devToolsUri': devToolsUri?.toString(),
          'startedAt': startedAt.toIso8601String(),
          'lastReloadMs': ?lastReload?.inMilliseconds,
        };
      case RunFailed(:final error):
        status = {'state': 'failed', 'error': error.forAgent()};
    }
    return AppMcpText(const JsonEncoder.withIndent('  ').convert(status));
  }
}

/// `app_logs`: the newest lines of the Run tab's log.
final class AppLogsTool implements AppMcpTool {
  /// Creates the tool.
  const AppLogsTool({required this._runs});

  final IAppRunRepository _runs;

  @override
  String get name => 'app_logs';

  @override
  String get description =>
      'Returns the newest lines of the app\'s log from the Run tab, oldest first. '
      'lines defaults to $appLogsDefaultLines (at most $appLogsMaxLines); errorsOnly keeps only '
      'error lines.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{
      'lines': {
        'type': 'integer',
        'description': 'How many lines to return; up to $appLogsMaxLines.',
      },
      'errorsOnly': {'type': 'boolean', 'description': 'Return only error lines.'},
    },
  };

  @override
  Future<AppMcpResult> call(AppMcpCaller caller, Map<String, Object?> arguments) async {
    final requested = arguments['lines'];
    final lines = (requested is num ? requested.toInt() : appLogsDefaultLines).clamp(
      1,
      appLogsMaxLines,
    );
    final errorsOnly = arguments['errorsOnly'] == true;
    // The errors are picked from the whole buffer, so a few of them are not lost among other lines.
    var entries = _runs.recentLogs(caller.projectId, limit: errorsOnly ? kRunLogLimit : lines);
    if (errorsOnly) {
      entries = entries.where((entry) => entry.level == LogLevel.error).toList();
    }
    entries = entries.sublist(math.max(0, entries.length - lines));
    if (entries.isEmpty) {
      return AppMcpText(errorsOnly ? 'No error lines in the log' : 'The log is empty');
    }
    return AppMcpText(entries.map(_format).join('\n'));
  }

  static String _format(LogEntry entry) {
    final time = entry.time;
    String two(int value) => value.toString().padLeft(2, '0');
    return '[${two(time.hour)}:${two(time.minute)}:${two(time.second)}] '
        '${entry.level.name}: ${entry.text}';
  }
}

/// `runtime_errors`: the structured errors of the run.
final class RuntimeErrorsTool implements AppMcpTool {
  /// Creates the tool.
  const RuntimeErrorsTool({required this._runs});

  final IAppRunRepository _runs;

  @override
  String get name => 'runtime_errors';

  @override
  String get description =>
      'Returns the errors the running app hit (framework exceptions, build failures): title, '
      'message, location and the top of the stack, the newest $runtimeErrorsLimit.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{},
  };

  @override
  Future<AppMcpResult> call(AppMcpCaller caller, Map<String, Object?> arguments) async {
    final errors = <RunError>[for (final entry in _runs.recentLogs(caller.projectId)) ?entry.error];
    // A run that failed to start reports its error in the state, perhaps also in the log.
    if (_runs.currentRun(caller.projectId) case RunFailed(:final error)
        when !errors.contains(error)) {
      errors.add(error);
    }
    if (errors.isEmpty) return const AppMcpText('No errors');
    final newest = errors.sublist(math.max(0, errors.length - runtimeErrorsLimit));
    return AppMcpText(newest.map((error) => error.forAgent()).join('\n\n---\n\n'));
  }
}

/// `hot_reload`.
final class HotReloadTool implements AppMcpTool {
  /// Creates the tool.
  const HotReloadTool({required this._runs});

  final IAppRunRepository _runs;

  @override
  String get name => 'hot_reload';

  @override
  String get description =>
      'Hot-reloads the app run of this chat\'s project (debug mode only), like the button in the '
      'Run tab. Call it after editing code.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{},
  };

  @override
  Future<AppMcpResult> call(AppMcpCaller caller, Map<String, Object?> arguments) async {
    final running = _running(_runs, caller);
    if (running == null) return _notRunning;
    if (running.mode != BuildMode.debug) {
      return const AppMcpError('Hot reload works only in debug mode');
    }
    final took = await _runs.hotReload(caller.projectId);
    if (took == Duration.zero) {
      return const AppMcpError('Hot reload failed; call app_logs to see why');
    }
    return AppMcpText('Reloaded in ${took.inMilliseconds} ms');
  }
}

/// `hot_restart`.
final class HotRestartTool implements AppMcpTool {
  /// Creates the tool.
  const HotRestartTool({required this._runs});

  final IAppRunRepository _runs;

  @override
  String get name => 'hot_restart';

  @override
  String get description =>
      'Hot-restarts the app run of this chat\'s project (debug mode only): the app state is '
      'lost. Use it when a hot reload is not enough, for example after changing main or a state '
      'initializer.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{},
  };

  @override
  Future<AppMcpResult> call(AppMcpCaller caller, Map<String, Object?> arguments) async {
    final running = _running(_runs, caller);
    if (running == null) return _notRunning;
    if (running.mode != BuildMode.debug) {
      return const AppMcpError('Hot restart works only in debug mode');
    }
    // The repository reports a failure only in the log: look for an error line it adds.
    final before = _runs.recentLogs(caller.projectId, limit: 1).lastOrNull?.seq ?? -1;
    await _runs.hotRestart(caller.projectId);
    final failed = _runs
        .recentLogs(caller.projectId)
        .any((entry) => entry.seq > before && entry.level == LogLevel.error);
    return failed
        ? const AppMcpError('Hot restart failed; call app_logs to see why')
        : const AppMcpText('Restarted');
  }
}

/// `screenshot`.
final class ScreenshotTool implements AppMcpTool {
  /// Creates the tool; [projectRoot] gives the folder of a project (`null` when it is unknown).
  const ScreenshotTool({required this._runs, required this._projectRoot});

  final IAppRunRepository _runs;
  final Future<String?> Function(int projectId) _projectRoot;

  @override
  String get name => 'screenshot';

  @override
  String get description =>
      'Takes a screenshot of the running app (debug mode only) and returns it as an image; the '
      'file is saved in the project and its path is in the text.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{},
  };

  @override
  Future<AppMcpResult> call(AppMcpCaller caller, Map<String, Object?> arguments) async {
    final running = _running(_runs, caller);
    if (running == null) return _notRunning;
    if (running.mode != BuildMode.debug) {
      return const AppMcpError('Screenshots work only in debug mode');
    }
    final relative = await _runs.screenshot(caller.projectId);
    final root = await _projectRoot(caller.projectId);
    if (relative == null || root == null) return const AppMcpError('Screenshot failed');
    final path = p.join(root, relative);
    try {
      return AppMcpImage(await File(path).readAsBytes(), caption: path);
    } on FileSystemException {
      return const AppMcpError('Screenshot failed');
    }
  }
}
