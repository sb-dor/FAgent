import 'dart:convert';
import 'dart:io';

import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_tool.dart';
import 'package:flutter_code_agent/src/feature/app_mcp_tools/data/run_tools.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/scripted_app_run_repository.dart';

const AppMcpCaller _chat1 = (sessionId: 10, projectId: 1);
const Device _device = Device(
  id: 'macos',
  name: 'macOS',
  platform: DevicePlatform.macos,
  kind: DeviceKind.running,
);

RunRunning _running({BuildMode mode = BuildMode.debug}) => RunRunning(
  device: _device,
  startedAt: DateTime.utc(2026, 11, 1, 9),
  mode: mode,
  vmServiceUri: Uri.parse('ws://127.0.0.1:1234/abc=/ws'),
  dtdUri: Uri.parse('ws://127.0.0.1:5678/def='),
  devToolsUri: Uri.parse('http://127.0.0.1:9100/'),
);

/// A repository that answers hot reload and restart as a test says, and logs [noise] meanwhile.
final class _AnsweringRuns extends ScriptedAppRunRepository {
  _AnsweringRuns({this.reloadTook = Duration.zero, this.restartTook = Duration.zero, this.noise})
    : super(step: const Duration(milliseconds: 1));

  final Duration reloadTook;
  final Duration restartTook;

  /// An error line the app prints while the call runs.
  final String? noise;

  final List<int> reloadCalls = <int>[];

  @override
  Future<Duration> hotReload(int projectId) async {
    reloadCalls.add(projectId);
    if (noise != null) addLog(projectId, LogLevel.error, noise!);
    return reloadTook;
  }

  @override
  Future<Duration> hotRestart(int projectId) async {
    if (noise != null) addLog(projectId, LogLevel.error, noise!);
    return restartTook;
  }
}

String _text(AppMcpResult result) => switch (result) {
  AppMcpText(:final text) => text,
  AppMcpError(:final message) => 'ERROR: $message',
  AppMcpImage(:final caption) => 'IMAGE $caption',
};

void main() {
  late ScriptedAppRunRepository runs;
  late Directory root;

  setUp(() {
    runs = ScriptedAppRunRepository(step: const Duration(milliseconds: 1));
    root = Directory.systemTemp.createTempSync('run_tools_test');
  });

  tearDown(() async {
    await runs.dispose();
    root.deleteSync(recursive: true);
  });

  AppMcpTool? Function(String) tools(IAppRunRepository repository) =>
      (name) => <AppMcpTool>[
        AppStatusTool(runs: repository),
        AppLogsTool(runs: repository),
        RuntimeErrorsTool(runs: repository),
        HotReloadTool(runs: repository),
        HotRestartTool(runs: repository),
        ScreenshotTool(runs: repository, projectRoot: (_) async => root.path),
      ].where((tool) => tool.name == name).firstOrNull;

  Future<AppMcpResult> call(
    String name, [
    Map<String, Object?> arguments = const {},
    AppMcpCaller caller = _chat1,
    IAppRunRepository? repository,
  ]) => tools(repository ?? runs)(name)!.call(caller, arguments);

  test('every tool has an object input schema', () {
    for (final name in <String>[
      'app_status',
      'app_logs',
      'runtime_errors',
      'hot_reload',
      'hot_restart',
      'screenshot',
    ]) {
      final schema = tools(runs)(name)!.inputSchema;
      expect(schema['type'], 'object', reason: name);
      expect(schema['properties'], isA<Map<String, Object?>>(), reason: name);
    }
  });

  group('app_status', () {
    test('says no app is running before and after a run', () async {
      expect(_text(await call('app_status')), 'No app is running');

      runs.setRunState(1, const RunStopped());

      expect(_text(await call('app_status')), 'No app is running');
    });

    test('reports a running app', () async {
      runs.setRunState(1, _running());

      final status = jsonDecode(_text(await call('app_status'))) as Map<String, Object?>;

      expect(status, containsPair('state', 'running'));
      expect(status, containsPair('device', 'macOS'));
      expect(status, containsPair('mode', 'debug'));
      expect(status, containsPair('vmServiceUri', 'ws://127.0.0.1:1234/abc=/ws'));
      expect(status, containsPair('dtdUri', 'ws://127.0.0.1:5678/def='));
      expect(status, containsPair('devToolsUri', 'http://127.0.0.1:9100/'));
    });

    test('reports a build and a failed start', () async {
      runs.setRunState(1, const RunBuilding(progress: 0.5, label: 'Xcode build'));
      expect(jsonDecode(_text(await call('app_status'))), {
        'state': 'building',
        'label': 'Xcode build',
        'progress': 0.5,
      });

      runs.setRunState(
        1,
        const RunFailed(
          error: RunError(title: 'Build failed', message: 'boom'),
        ),
      );
      final failed = jsonDecode(_text(await call('app_status'))) as Map<String, Object?>;
      expect(failed['state'], 'failed');
      expect(failed['error'], contains('Build failed'));
    });
  });

  group('the run of another project', () {
    setUp(() {
      runs
        ..setRunState(2, _running())
        ..addLog(
          2,
          LogLevel.error,
          'project two broke',
          error: const RunError(title: 'Two', message: 'm'),
        );
    });

    test('is not seen by the caller of project 1', () async {
      expect(_text(await call('app_status')), 'No app is running');
      expect(_text(await call('app_logs')), 'The log is empty');
      expect(_text(await call('runtime_errors')), 'No errors');
    });

    test('is never touched by hot reload, hot restart or screenshot', () async {
      expect(_text(await call('hot_reload')), 'ERROR: App is not running');
      expect(_text(await call('hot_restart')), 'ERROR: App is not running');
      expect(_text(await call('screenshot')), 'ERROR: App is not running');

      expect(runs.screenshotCalls, isEmpty);
      // The scripted run logs a line for every reload or restart it does.
      expect(runs.recentLogs(2).map((log) => log.text), ['project two broke']);
      expect(runs.currentRun(2), _running());
    });

    test('is the one project 2 acts on', () async {
      const chat2 = (sessionId: 11, projectId: 2);

      expect(_text(await call('hot_reload', {}, chat2)), 'Reloaded in 180 ms');
      expect(runs.recentLogs(1), isEmpty);
    });
  });

  group('hot_reload and hot_restart', () {
    test('refuse while the app is building, stopped or failed', () async {
      for (final state in <RunState>[
        const RunIdle(),
        const RunBuilding(),
        const RunStopped(),
        const RunFailed(
          error: RunError(title: 't', message: 'm'),
        ),
      ]) {
        runs.setRunState(1, state);

        expect(_text(await call('hot_reload')), 'ERROR: App is not running', reason: '$state');
        expect(_text(await call('hot_restart')), 'ERROR: App is not running', reason: '$state');
      }
      expect(runs.recentLogs(1), isEmpty);
    });

    test('refuse outside debug mode without touching the app', () async {
      for (final mode in <BuildMode>[BuildMode.profile, BuildMode.release]) {
        runs.setRunState(1, _running(mode: mode));

        expect(_text(await call('hot_reload')), 'ERROR: Hot reload works only in debug mode');
        expect(_text(await call('hot_restart')), 'ERROR: Hot restart works only in debug mode');
      }
      expect(runs.recentLogs(1), isEmpty);
    });

    test('reload reports how long it took', () async {
      runs.setRunState(1, _running());

      expect(_text(await call('hot_reload')), 'Reloaded in 180 ms');
      expect(runs.recentLogs(1).map((log) => log.text), ['Reloaded 3 of 812 libraries in 180ms.']);
    });

    test('reload that the repository reports as failed says to look at the log', () async {
      final failing = _AnsweringRuns()..setRunState(1, _running());
      addTearDown(failing.dispose);

      expect(
        _text(await call('hot_reload', {}, _chat1, failing)),
        'ERROR: Hot reload failed; call app_logs to see why',
      );
      expect(failing.reloadCalls, [1]);
    });

    test('an error line the app prints during a successful reload does not fail it', () async {
      final noisy = _AnsweringRuns(reloadTook: const Duration(milliseconds: 90), noise: 'boom')
        ..setRunState(1, _running());
      addTearDown(noisy.dispose);

      expect(_text(await call('hot_reload', {}, _chat1, noisy)), 'Reloaded in 90 ms');
    });

    test('restart reports how long it took', () async {
      runs.setRunState(1, _running());

      expect(_text(await call('hot_restart')), 'Restarted in 640 ms');
    });

    test('an error line the app prints during a successful restart does not fail it', () async {
      final noisy = _AnsweringRuns(restartTook: const Duration(milliseconds: 500), noise: 'boom')
        ..setRunState(1, _running());
      addTearDown(noisy.dispose);

      expect(_text(await call('hot_restart', {}, _chat1, noisy)), 'Restarted in 500 ms');
    });

    test('a restart the repository reports as failed fails, though nothing was logged', () async {
      final failing = _AnsweringRuns()..setRunState(1, _running());
      addTearDown(failing.dispose);

      expect(
        _text(await call('hot_restart', {}, _chat1, failing)),
        'ERROR: Hot restart failed; call app_logs to see why',
      );
      expect(failing.recentLogs(1), isEmpty);
    });
  });

  group('app_logs', () {
    setUp(() {
      for (var i = 0; i < 12; i++) {
        runs.addLog(1, i.isEven ? LogLevel.error : LogLevel.info, 'line $i');
      }
    });

    List<String> lines(AppMcpResult result) => _text(result).split('\n');

    test('returns the last lines, oldest first', () async {
      final result = lines(await call('app_logs', {'lines': 3}));

      expect(result, hasLength(3));
      expect(result[0], endsWith('info: line 9'));
      expect(result[2], endsWith('info: line 11'));
    });

    test('errorsOnly returns the last N error entries', () async {
      final result = lines(await call('app_logs', {'lines': 5, 'errorsOnly': true}));

      expect(result, hasLength(5));
      expect(result.every((line) => line.contains('error: ')), isTrue);
      expect(result.first, endsWith('error: line 2'));
      expect(result.last, endsWith('error: line 10'));
    });

    test('errorsOnly finds errors that are older than the last N lines', () async {
      final result = lines(await call('app_logs', {'lines': 2, 'errorsOnly': true}));

      expect(result.map((line) => line.split(': ').last), ['line 8', 'line 10']);
    });

    test('defaults to 200 lines and accepts a number given as a double', () async {
      expect(lines(await call('app_logs')), hasLength(12));
      expect(lines(await call('app_logs', {'lines': 4.0})), hasLength(4));
    });

    test('clamps lines to the range 1 to 1000', () async {
      for (var i = 0; i < 1100; i++) {
        runs.addLog(1, LogLevel.info, 'more $i');
      }

      expect(lines(await call('app_logs', {'lines': 5000})), hasLength(appLogsMaxLines));
      expect(lines(await call('app_logs', {'lines': 0})), hasLength(1));
      expect(lines(await call('app_logs', {'lines': -4})), hasLength(1));
    });

    test('says when there is nothing to show', () async {
      runs.setRunState(3, const RunStopped());

      expect(_text(await call('app_logs', {}, (sessionId: 1, projectId: 3))), 'The log is empty');
      expect(
        _text(await call('app_logs', {'errorsOnly': true}, (sessionId: 1, projectId: 4))),
        'No error lines in the log',
      );
    });
  });

  group('the previous run', () {
    Future<void> startAgain() async {
      await runs.start(1, device: _device, mode: BuildMode.debug, target: 'lib/main.dart');
    }

    setUp(() {
      runs
        ..addLog(
          1,
          LogLevel.error,
          'old overflow',
          error: const RunError(title: 'Old error', message: 'fixed since'),
        )
        ..setRunState(1, _running());
    });

    test('is not in app_logs or runtime_errors once a new run starts', () async {
      expect(_text(await call('runtime_errors')), contains('Old error'));

      await startAgain();
      runs.addLog(1, LogLevel.info, 'fresh line');

      final logs = _text(await call('app_logs'));
      expect(logs, contains('fresh line'));
      expect(logs, isNot(contains('old overflow')));
      expect(_text(await call('app_logs', {'errorsOnly': true})), 'No error lines in the log');
      expect(_text(await call('runtime_errors')), 'No errors');
    });

    test('the errors of the new run are returned', () async {
      await startAgain();
      runs.addLog(
        1,
        LogLevel.error,
        'new overflow',
        error: const RunError(title: 'New error', message: 'still broken'),
      );

      final text = _text(await call('runtime_errors'));

      expect(text, contains('New error'));
      expect(text, isNot(contains('Old error')));
    });

    test('stays readable after the run ended', () async {
      await startAgain();
      runs.addLog(
        1,
        LogLevel.error,
        'late',
        error: const RunError(title: 'Late', message: 'm'),
      );
      await runs.stop(1);

      expect(_text(await call('runtime_errors')), contains('Late'));
      expect(_text(await call('runtime_errors')), isNot(contains('Old error')));
    });
  });

  group('runtime_errors', () {
    test('lists the errors of the run as text for the agent', () async {
      runs
        ..addLog(1, LogLevel.info, 'not an error')
        ..addLog(
          1,
          LogLevel.error,
          'overflow',
          error: const RunError(
            title: 'Layout overflow',
            message: 'A RenderFlex overflowed by 24 pixels.',
            file: 'lib/booking_card.dart',
            line: 42,
            stack: '#0 RenderFlex.paint\n#1 BookingCard.build',
          ),
        );

      final text = _text(await call('runtime_errors'));

      expect(text, startsWith('Layout overflow\nA RenderFlex overflowed by 24 pixels.'));
      expect(text, contains('Location: lib/booking_card.dart:42'));
      expect(text, contains('#1 BookingCard.build'));
      expect(text, isNot(contains('not an error')));
    });

    test('adds the error of a failed start once', () async {
      const error = RunError(title: 'Build failed', message: 'boom');
      runs.setRunState(1, const RunFailed(error: error));

      expect(_text(await call('runtime_errors')), startsWith('Build failed\nboom'));

      runs.addLog(1, LogLevel.error, 'Build failed: boom', error: error);

      expect('Build failed\nboom'.allMatches(_text(await call('runtime_errors'))), hasLength(1));
    });

    test('keeps the newest ten', () async {
      for (var i = 0; i < 15; i++) {
        runs.addLog(
          1,
          LogLevel.error,
          'e$i',
          error: RunError(title: 'Error $i', message: 'm'),
        );
      }

      final text = _text(await call('runtime_errors'));

      expect(text, isNot(contains('Error 4\n')));
      expect(text, contains('Error 5\n'));
      expect(text, contains('Error 14\n'));
    });

    test('says when there are none', () async {
      expect(_text(await call('runtime_errors')), 'No errors');
    });
  });

  group('screenshot', () {
    test('returns the PNG with the saved path as caption', () async {
      final file = File(p.join(root.path, ScriptedAppRunRepository.defaultScreenshotPath))
        ..createSync(recursive: true)
        ..writeAsBytesSync([137, 80, 78, 71]);
      runs.setRunState(1, _running());

      final result = await call('screenshot');

      expect(result, isA<AppMcpImage>());
      final image = result as AppMcpImage;
      expect(image.png, [137, 80, 78, 71]);
      expect(image.caption, file.path);
      expect(runs.screenshotCalls, [1]);
    });

    test('says it failed when the repository gives no shot', () async {
      runs
        ..setRunState(1, _running())
        ..screenshotPath = null;

      expect(_text(await call('screenshot')), 'ERROR: Screenshot failed');
    });

    test('says it failed when the saved file is gone', () async {
      runs.setRunState(1, _running());

      expect(_text(await call('screenshot')), 'ERROR: Screenshot failed');
    });

    test('is for a running debug app only', () async {
      expect(_text(await call('screenshot')), 'ERROR: App is not running');

      runs.setRunState(1, _running(mode: BuildMode.profile));
      expect(_text(await call('screenshot')), 'ERROR: Screenshots work only in debug mode');
      expect(runs.screenshotCalls, isEmpty);
    });
  });
}
