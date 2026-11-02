import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/flutter_error_listener.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_arguments.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l/l.dart' show l;
import 'package:path/path.dart' as p;

import '../../support/scripted_daemon_process.dart';
import '../../support/scripted_vm_service.dart';

const Device _macos = Device(
  id: 'macos',
  name: 'macOS',
  platform: DevicePlatform.macos,
  kind: DeviceKind.running,
);

Map<String, Object?> _event(
  String name, [
  Map<String, Object?> params = const <String, Object?>{},
]) => <String, Object?>{'event': name, 'params': params};

void main() {
  group('splitArgs', () {
    test('splits on spaces, groups quotes and honours backslashes', () {
      expect(splitArgs('--a "b c" \'d\' e\\ f'), <String>['--a', 'b c', 'd', 'e f']);
    });

    test('an unclosed quote is null', () {
      expect(splitArgs('"x'), isNull);
      expect(splitArgs("--a 'b"), isNull);
    });

    test('an empty text is no arguments', () {
      expect(splitArgs(''), isEmpty);
      expect(splitArgs('   '), isEmpty);
    });

    test('a backslash escapes a quote inside double quotes', () {
      expect(splitArgs(r'"a \"b\" c"'), <String>['a "b" c']);
    });
  });

  group('RunArguments.toFlutterArgs', () {
    test('flavor, every define, then the extra arguments', () {
      expect(
        const RunArguments(
          flavor: 'dev',
          dartDefines: <String>['A=1', 'B=two words'],
          extraArgs: '--verbose --route "/a b"',
        ).toFlutterArgs(),
        <String>[
          '--flavor',
          'dev',
          '--dart-define',
          'A=1',
          '--dart-define',
          'B=two words',
          '--verbose',
          '--route',
          '/a b',
        ],
      );
    });

    test('nothing set is no arguments; unparsable extra arguments are dropped', () {
      expect(const RunArguments().toFlutterArgs(), isEmpty);
      expect(const RunArguments(extraArgs: '"oops').toFlutterArgs(), isEmpty);
    });
  });

  group('AppRunRepositoryImpl', () {
    late io.Directory root;
    late Map<int, String> paths;
    late String? flutterPath;
    late List<ScriptedDaemonProcess> started;
    late void Function(ScriptedDaemonProcess process, Map<String, Object?> request) onRequest;
    late AppRunRepositoryImpl repository;
    late List<Uri> opened;
    late DateTime clock;
    late FlutterErrorListenerConnect connectErrors;
    late List<Uri> connectedTo;
    final subscriptions = <StreamSubscription<Object?>>[];

    ScriptedDaemonProcess create() {
      final process = ScriptedDaemonProcess();
      process.onRequest = (request) => onRequest(process, request);
      return process;
    }

    String project(String name, {String? pubspecName}) {
      final dir = io.Directory(p.join(root.path, name))..createSync();
      if (pubspecName != null) {
        io.File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('name: $pubspecName\n');
      }
      return dir.path;
    }

    List<RunState> states(int projectId) {
      final out = <RunState>[];
      subscriptions.add(repository.watchRun(projectId).listen(out.add));
      return out;
    }

    List<LogEntry> logs(int projectId) {
      final out = <LogEntry>[];
      subscriptions.add(repository.logs(projectId).listen(out.add));
      return out;
    }

    Future<void> startRun(
      int projectId, {
      RunArguments arguments = const RunArguments(),
      BuildMode mode = BuildMode.debug,
    }) async {
      await repository.start(
        projectId,
        device: _macos,
        mode: mode,
        target: 'lib/main.dart',
        arguments: arguments,
      );
      await pumpEventQueue();
    }

    Future<void> emit(
      ScriptedDaemonProcess process,
      String name, [
      Map<String, Object?>? params,
    ]) async {
      process.emit(_event(name, params ?? const <String, Object?>{}));
      await pumpEventQueue();
    }

    /// Brings [process] up to `app.started` with all three addresses.
    Future<void> launch(ScriptedDaemonProcess process, {String appId = 'app-1'}) async {
      await emit(process, 'app.start', <String, Object?>{'appId': appId, 'deviceId': 'macos'});
      await emit(process, 'app.debugPort', <String, Object?>{
        'appId': appId,
        'port': 1234,
        'wsUri': 'ws://127.0.0.1:1234/abc=/ws',
      });
      await emit(process, 'app.started', <String, Object?>{'appId': appId});
    }

    setUp(() {
      root = io.Directory.systemTemp.createTempSync('app_run_repository_test');
      paths = <int, String>{
        1: project('one', pubspecName: 'demo_app'),
        2: project('two', pubspecName: 'other_app'),
      };
      flutterPath = '/opt/flutter/bin/flutter';
      started = <ScriptedDaemonProcess>[];
      onRequest = (process, request) {
        if (request['method'] == 'app.stop') {
          process
            ..respond(request['id']! as int, result: true)
            ..exit(0);
        }
      };
      opened = <Uri>[];
      clock = DateTime(2026, 10, 31, 9, 5, 7);
      // Unless a test connects, the VM service never answers: the output text is all there is.
      connectErrors = (_) => Completer<IFlutterErrorListener>().future;
      connectedTo = <Uri>[];
      repository = AppRunRepositoryImpl(
        projectPath: (id) async => paths[id],
        flutter: (_) => flutterPath,
        environment: const <String, String>{'PATH': '/usr/bin'},
        start: scriptedStarter(create, started: started),
        stopTimeout: const Duration(milliseconds: 50),
        restartTimeout: const Duration(milliseconds: 50),
        openUrl: (url) async => opened.add(url),
        now: () => clock,
        connectErrors: (uri) {
          connectedTo.add(uri);
          return connectErrors(uri);
        },
      );
    });

    tearDown(() async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      subscriptions.clear();
      await repository.dispose();
      root.deleteSync(recursive: true);
    });

    test('is not a preview', () {
      expect(repository.isPreview, isFalse);
    });

    test('runs `flutter run --machine` in the project folder with the arguments', () async {
      final log = logs(1);
      await startRun(
        1,
        arguments: const RunArguments(flavor: 'dev', dartDefines: <String>['A=1']),
      );

      final process = started.single;
      expect(process.executable, '/opt/flutter/bin/flutter');
      expect(process.arguments, <String>[
        'run',
        '--machine',
        '-d',
        'macos',
        '--debug',
        '-t',
        'lib/main.dart',
        '--flavor',
        'dev',
        '--dart-define',
        'A=1',
      ]);
      expect(process.workingDirectory, paths[1]);
      expect(process.environment, <String, String>{'PATH': '/usr/bin'});
      expect(log.first.level, LogLevel.info);
      expect(
        log.first.text,
        '/opt/flutter/bin/flutter run --machine -d macos --debug -t lib/main.dart '
        '--flavor dev --dart-define A=1',
      );
    });

    test('the build mode is passed as a flag', () async {
      await startRun(1, mode: BuildMode.profile);

      expect(started.single.arguments, contains('--profile'));
    });

    test('events move the run from building to running with the three addresses', () async {
      final seen = states(1);
      await pumpEventQueue();
      await startRun(1);
      final process = started.single;

      await emit(process, 'app.start', <String, Object?>{'appId': 'app-1', 'deviceId': 'macos'});
      await emit(process, 'app.progress', <String, Object?>{
        'appId': 'app-1',
        'id': '0',
        'progressId': null,
        'message': 'Building macOS application...',
        'finished': false,
      });
      await emit(process, 'app.progress', <String, Object?>{
        'appId': 'app-1',
        'id': '0',
        'finished': true,
      });
      await emit(process, 'app.debugPort', <String, Object?>{
        'appId': 'app-1',
        'port': 1234,
        'wsUri': 'ws://127.0.0.1:1234/abc=/ws',
      });
      await emit(process, 'app.dtd', <String, Object?>{
        'appId': 'app-1',
        'uri': 'ws://127.0.0.1:5678/def=',
      });
      await emit(process, 'app.devTools', <String, Object?>{
        'appId': 'app-1',
        'uri': 'http://127.0.0.1:9100?uri=ws://127.0.0.1:1234/abc=/ws',
      });
      await emit(process, 'app.started', <String, Object?>{'appId': 'app-1'});

      expect(seen, hasLength(4));
      expect(seen.sublist(0, 3), <RunState>[
        const RunIdle(),
        const RunBuilding(),
        const RunBuilding(label: 'Building macOS application...'),
      ]);
      final running = seen.last as RunRunning;
      expect(running.device, _macos);
      expect(running.mode, BuildMode.debug);
      expect(running.vmServiceUri, Uri.parse('ws://127.0.0.1:1234/abc=/ws'));
      expect(running.dtdUri, Uri.parse('ws://127.0.0.1:5678/def='));
      expect(
        running.devToolsUri,
        Uri.parse('http://127.0.0.1:9100?uri=ws://127.0.0.1:1234/abc=/ws'),
      );
      expect(running.lastReload, isNull);
    });

    test('an address that comes after app.started gives a new running state with it', () async {
      final seen = states(1);
      await startRun(1);
      final process = started.single;
      await launch(process);

      await emit(process, 'app.devTools', <String, Object?>{
        'appId': 'app-1',
        'uri': 'http://127.0.0.1:9100',
      });

      final last = seen.last as RunRunning;
      expect(last.devToolsUri, Uri.parse('http://127.0.0.1:9100'));
      expect(last.vmServiceUri, Uri.parse('ws://127.0.0.1:1234/abc=/ws'));
      expect((seen[seen.length - 2] as RunRunning).devToolsUri, isNull);
    });

    test('an error block in app.log comes out as one line with the error', () async {
      final log = logs(1);
      await startRun(1);
      final process = started.single;
      await launch(process);
      final before = log.length;

      for (final line in <String>[
        'flutter: ══╡ EXCEPTION CAUGHT BY RENDERING LIBRARY ╞═════════════════════════',
        'flutter: The following assertion was thrown during layout:',
        'flutter: A RenderFlex overflowed by 24 pixels on the right.',
        'flutter: ════════════════════════════════════════════════════════════════════',
      ]) {
        await emit(process, 'app.log', <String, Object?>{'appId': 'app-1', 'log': line});
      }

      final added = log.sublist(before);
      expect(added, hasLength(1));
      expect(added.single.level, LogLevel.error);
      expect(added.single.error, isNotNull);
      expect(added.single.error!.title, 'Layout overflow');
    });

    test(
      'currentRun and recentLogs give the state and the newest lines without a stream',
      () async {
        expect(repository.currentRun(1), const RunIdle());
        expect(repository.recentLogs(1), isEmpty);

        await startRun(1);
        final process = started.single;
        await launch(process);
        process
          ..emitLine('first')
          ..emitLine('second')
          ..emitLine('third');
        await pumpEventQueue();

        expect(repository.currentRun(1), isA<RunRunning>());
        expect(repository.currentRun(2), const RunIdle());
        final all = repository.recentLogs(1);
        expect(all.map((entry) => entry.text).toList().sublist(all.length - 3), [
          'first',
          'second',
          'third',
        ]);
        expect(repository.recentLogs(1, limit: 2).map((entry) => entry.text), ['second', 'third']);
        expect(repository.recentLogs(1, limit: 0), isEmpty);
        expect(repository.recentLogs(2), isEmpty);
      },
    );

    test(
      'recentLogs holds only the lines of the current run, the last run once it ended',
      () async {
        await startRun(1);
        final first = started.single;
        await launch(first);
        first.emitLine('from the first run');
        await pumpEventQueue();
        expect(repository.recentLogs(1).map((entry) => entry.text), contains('from the first run'));

        await startRun(1);
        final second = started.last;
        expect(second, isNot(same(first)));
        second.emitLine('from the second run');
        await pumpEventQueue();

        final texts = repository.recentLogs(1).map((entry) => entry.text).toList();
        expect(texts, contains('from the second run'));
        expect(texts.any((text) => text.contains('first run')), isFalse);
        expect(texts.first, startsWith('/opt/flutter/bin/flutter run'));

        await repository.stop(1);
        await pumpEventQueue();
        expect(
          repository.recentLogs(1).map((entry) => entry.text),
          contains('from the second run'),
        );
      },
    );

    test('daemon.logMessage and output outside the protocol go to the log', () async {
      final log = logs(1);
      await startRun(1);
      final process = started.single;

      await emit(process, 'daemon.logMessage', <String, Object?>{
        'level': 'status',
        'message': 'Launching lib/main.dart on macOS in debug mode...',
      });
      process
        ..emitLine('Some plain stdout line')
        ..emitError('Some stderr line');
      await pumpEventQueue();

      final texts = log.map((entry) => entry.text).toList();
      expect(texts, contains('Launching lib/main.dart on macOS in debug mode...'));
      expect(texts, contains('Some plain stdout line'));
      final stderr = log.firstWhere((entry) => entry.text == 'Some stderr line');
      expect(stderr.level, LogLevel.error);
    });

    test('a huge line is cut at kLogLineLimit characters and says how much is left out', () async {
      final log = logs(1);
      await startRun(1);
      final process = started.single;
      await launch(process);

      await emit(process, 'app.log', <String, Object?>{
        'appId': 'app-1',
        'log': 'flutter: ${'x' * (kLogLineLimit + 500)}',
      });
      process.emitLine('y' * (kLogLineLimit + 1));
      await pumpEventQueue();

      // The cut comes first, then the parser drops the `flutter: ` of the print.
      final printed = log.firstWhere((entry) => entry.text.startsWith('x'));
      expect(printed.text, '${'x' * (kLogLineLimit - 9)}… (509 more characters)');
      final plain = log.firstWhere((entry) => entry.text.startsWith('y'));
      expect(plain.text, '${'y' * kLogLineLimit}… (1 more character)');
    });

    test('hotReload sends app.restart and records the time on success', () async {
      final seen = states(1);
      await startRun(1);
      final process = started.single;
      await launch(process);
      onRequest = (process, request) {
        if (request['method'] == 'app.restart') {
          process.respond(
            request['id']! as int,
            result: <String, Object?>{'code': 0, 'message': ''},
          );
        }
      };

      final took = await repository.hotReload(1);
      await pumpEventQueue();

      final request = process.sent.lastWhere((request) => request['method'] == 'app.restart');
      expect(request['params'], <String, Object?>{
        'appId': 'app-1',
        'fullRestart': false,
        'reason': 'manual',
      });
      final last = seen.last as RunRunning;
      expect(last.lastReload, took);
      expect(last.vmServiceUri, Uri.parse('ws://127.0.0.1:1234/abc=/ws'));
    });

    test('hotRestart sends a full restart', () async {
      final seen = states(1);
      await startRun(1);
      final process = started.single;
      await launch(process);
      onRequest = (process, request) {
        if (request['method'] == 'app.restart') {
          process.respond(
            request['id']! as int,
            result: <String, Object?>{'code': 0, 'message': ''},
          );
        }
      };

      final took = await repository.hotRestart(1);
      await pumpEventQueue();

      expect(took, greaterThan(Duration.zero));
      expect(took, (seen.last as RunRunning).lastReload);
      final request = process.sent.lastWhere((request) => request['method'] == 'app.restart');
      expect((request['params']! as Map<String, Object?>)['fullRestart'], isTrue);
      expect((seen.last as RunRunning).lastReload, isNotNull);
    });

    test('a rejected hot reload logs "Hot reload failed" and keeps the app running', () async {
      final seen = states(1);
      final log = logs(1);
      await startRun(1);
      final process = started.single;
      await launch(process);
      onRequest = (process, request) {
        if (request['method'] == 'app.restart') {
          process.respond(
            request['id']! as int,
            result: <String, Object?>{'code': 1, 'message': 'Reload rejected'},
          );
        }
      };
      final statesBefore = seen.length;

      final took = await repository.hotReload(1);
      await pumpEventQueue();

      expect(took, Duration.zero);
      expect(seen.length, statesBefore);
      expect(seen.last, isA<RunRunning>());
      final failure = log.last;
      expect(failure.level, LogLevel.error);
      expect(failure.error, const RunError(title: 'Hot reload failed', message: 'Reload rejected'));
    });

    test(
      'a hot restart answered with an error logs "Hot restart failed" and does not throw',
      () async {
        final log = logs(1);
        await startRun(1);
        final process = started.single;
        await launch(process);
        onRequest = (process, request) {
          if (request['method'] == 'app.restart') {
            process.respond(request['id']! as int, error: 'no isolate');
          }
        };

        final took = await repository.hotRestart(1);
        await pumpEventQueue();

        expect(took, Duration.zero);
        expect(log.last.error?.title, 'Hot restart failed');
      },
    );

    test('a hot reload that gets no answer times out and keeps the app running', () async {
      final seen = states(1);
      final log = logs(1);
      await startRun(1);
      final process = started.single;
      await launch(process);
      onRequest = (_, _) {};

      final took = await repository.hotReload(1);
      await pumpEventQueue();

      expect(took, Duration.zero);
      expect(seen.last, isA<RunRunning>());
      expect(log.last.error, const RunError(title: 'Hot reload failed', message: 'timed out'));
      expect(log.last.text, 'Hot reload failed: timed out');
    });

    test('hotReload and hotRestart do nothing unless the app is running', () async {
      await startRun(1);

      expect(await repository.hotReload(1), Duration.zero);
      expect(await repository.hotRestart(1), Duration.zero);
      expect(started.single.sent, isEmpty);
      expect(await repository.hotReload(2), Duration.zero);
    });

    test('stop sends app.stop, kills the group and ends stopped', () async {
      final seen = states(1);
      await startRun(1);
      final process = started.single;
      await launch(process);

      await repository.stop(1);
      await pumpEventQueue();

      final request = process.sent.singleWhere((request) => request['method'] == 'app.stop');
      expect(request['params'], <String, Object?>{'appId': 'app-1'});
      expect(process.stopped, isTrue);
      expect(seen.last, const RunStopped());
    });

    test('stop kills a process that does not answer app.stop within the timeout', () async {
      onRequest = (_, _) {};
      final seen = states(1);
      await startRun(1);
      final process = started.single;
      await launch(process);

      await repository.stop(1);
      await pumpEventQueue();

      expect(process.stopped, isTrue);
      expect(seen.last, const RunStopped());
    });

    test('stop during the build kills the process and ends stopped', () async {
      final seen = states(1);
      await startRun(1);

      await repository.stop(1);
      await pumpEventQueue();

      expect(started.single.stopped, isTrue);
      expect(seen.last, const RunStopped());
    });

    test('stop does nothing when nothing runs', () async {
      final seen = states(1);
      await pumpEventQueue();

      await repository.stop(1);
      await pumpEventQueue();

      expect(seen, <RunState>[const RunIdle()]);
    });

    test('a process that dies during the build fails with the first compile error', () async {
      final seen = states(1);
      await startRun(1);
      final process = started.single;
      await emit(process, 'app.start', <String, Object?>{'appId': 'app-1'});

      process.emitError("lib/main.dart:3:1: Error: Expected ';' after this.");
      await pumpEventQueue();
      process.exit(1);
      await pumpEventQueue();

      final failed = seen.last as RunFailed;
      expect(failed.error.title, 'Compilation error');
      expect(failed.error.file, 'lib/main.dart');
      expect(failed.error.line, 3);
      expect(process.stopped, isTrue, reason: 'an exit before app.started ends the group too');
    });

    test('a build that fails without a compile error logs the stop error and the last error lines '
        'as one line to send', () async {
      final seen = states(1);
      final log = logs(1);
      await startRun(1);
      final process = started.single;
      await emit(process, 'app.start', <String, Object?>{'appId': 'app-1'});

      process
        ..emitError('** BUILD FAILED **')
        ..emitError('Command PhaseScriptExecution failed with a nonzero exit code');
      await pumpEventQueue();
      // What flutter run --machine sends when `flutter build` throws a ToolExit.
      await emit(process, 'app.stop', <String, Object?>{
        'appId': 'app-1',
        'error': 'Build process failed',
      });
      process.exit(1);
      await pumpEventQueue();

      final failed = seen.last as RunFailed;
      expect(failed.error.title, 'Build failed');
      expect(
        failed.error.message,
        'Build process failed\n'
        '** BUILD FAILED **\n'
        'Command PhaseScriptExecution failed with a nonzero exit code',
      );
      final sendable = log.where((entry) => entry.error != null).toList();
      expect(sendable, hasLength(1));
      expect(sendable.single.level, LogLevel.error);
      expect(sendable.single.error, failed.error);
      expect(process.stopped, isTrue);
    });

    test('a build that dies without app.stop fails with the last error lines', () async {
      final seen = states(1);
      final log = logs(1);
      await startRun(1);

      started.single
        ..emitError('** BUILD FAILED **')
        ..emitError('Command PhaseScriptExecution failed with a nonzero exit code');
      await pumpEventQueue();
      started.single.exit(1);
      await pumpEventQueue();

      final failed = seen.last as RunFailed;
      expect(failed.error.title, 'Build failed');
      expect(failed.error.message, contains('** BUILD FAILED **'));
      expect(failed.error.message, contains('PhaseScriptExecution'));
      expect(log.last.error, failed.error);
    });

    test('a failure keeps only the last error lines', () async {
      final seen = states(1);
      await startRun(1);

      for (var i = 0; i < 30; i++) {
        started.single.emitError('error line $i');
      }
      await pumpEventQueue();
      started.single.exit(1);
      await pumpEventQueue();

      final lines = (seen.last as RunFailed).error.message.split('\n');
      expect(lines, hasLength(20));
      expect(lines.first, 'error line 10');
      expect(lines.last, 'error line 29');
    });

    test('a compile error is not logged a second time when the build fails', () async {
      final log = logs(1);
      await startRun(1);
      started.single.emitError("lib/main.dart:3:1: Error: Expected ';' after this.");
      await pumpEventQueue();
      started.single.exit(1);
      await pumpEventQueue();

      expect(log.where((entry) => entry.error != null), hasLength(1));
    });

    test('app.stop with an error before app.started fails with that error', () async {
      final seen = states(1);
      await startRun(1);
      final process = started.single;

      await emit(process, 'app.stop', <String, Object?>{
        'appId': 'app-1',
        'error': 'Unable to start the app on the device.',
      });
      process.exit(1);
      await pumpEventQueue();

      expect(
        seen.last,
        const RunFailed(
          error: RunError(title: 'Build failed', message: 'Unable to start the app on the device.'),
        ),
      );
      expect(process.stopped, isTrue);
    });

    test('a process group that cannot be stopped is logged, not thrown', () async {
      final seen = states(1);
      await startRun(1);
      final process = started.single..stopError = StateError('kill failed');
      await launch(process);

      process
        ..emitError('Lost connection to device.')
        ..exit(1);
      await pumpEventQueue();

      expect(process.stopped, isTrue);
      expect((seen.last as RunFailed).error.title, 'App exited');
    });

    test('an app.stop whose group cannot be stopped is logged, not thrown', () async {
      final seen = states(1);
      await startRun(1);
      final process = started.single..stopError = StateError('kill failed');
      await launch(process);

      await emit(process, 'app.stop', <String, Object?>{'appId': 'app-1'});
      process.exit(0);
      await pumpEventQueue();

      expect(process.stopped, isTrue);
      expect(seen.last, const RunStopped());
    });

    test('an exit with code 0 after app.started without a stop ends stopped', () async {
      final seen = states(1);
      await startRun(1);
      final process = started.single;
      await launch(process);

      await emit(process, 'app.stop', <String, Object?>{'appId': 'app-1'});
      process.exit(0);
      await pumpEventQueue();

      expect(seen.last, const RunStopped());
    });

    test('a crash after app.started fails as "App exited"', () async {
      final seen = states(1);
      final log = logs(1);
      await startRun(1);
      final process = started.single;
      await launch(process);

      process.emitError('Lost connection to device.');
      await pumpEventQueue();
      process.exit(1);
      await pumpEventQueue();

      final failed = seen.last as RunFailed;
      expect(failed.error.title, 'App exited');
      expect(failed.error.message, contains('Lost connection to device.'));
      expect(process.stopped, isTrue, reason: 'the leftovers of the group are ended too');
      expect(log.last.error, failed.error, reason: 'the failure can be sent to the agent');
    });

    test('an unhandled exception still being collected is flushed on exit', () async {
      final log = logs(1);
      await startRun(1);
      final process = started.single;
      await launch(process);

      await emit(process, 'app.log', <String, Object?>{
        'appId': 'app-1',
        'log':
            '[ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled Exception: Bad state: x',
        'error': true,
      });
      await emit(process, 'app.log', <String, Object?>{
        'appId': 'app-1',
        'log': '#0      main (package:demo_app/main.dart:5:3)',
        'error': true,
      });
      process.exit(0);
      await pumpEventQueue();

      final error = log.lastWhere((entry) => entry.error != null).error!;
      expect(error.file, 'lib/main.dart');
    });

    test('no project folder fails with "Project folder not found"', () async {
      final seen = states(3);
      await repository.start(3, device: _macos, mode: BuildMode.debug, target: 'lib/main.dart');
      await pumpEventQueue();

      expect(started, isEmpty);
      final error = (seen.last as RunFailed).error;
      expect(error.title, 'Project folder not found');
      expect(error.message, 'The folder of this project is unknown.');
    });

    test('a folder that is gone fails with "Project folder not found"', () async {
      paths[3] = p.join(root.path, 'missing');
      final seen = states(3);
      await repository.start(3, device: _macos, mode: BuildMode.debug, target: 'lib/main.dart');
      await pumpEventQueue();

      expect(started, isEmpty);
      final error = (seen.last as RunFailed).error;
      expect(error.title, 'Project folder not found');
      expect(error.message, '${paths[3]} does not exist.');
    });

    test('no Flutter SDK fails with "Flutter SDK not found"', () async {
      flutterPath = null;
      final seen = states(1);
      await startRun(1);

      expect(started, isEmpty);
      final error = (seen.last as RunFailed).error;
      expect(error.title, 'Flutter SDK not found');
      expect(error.message, contains('PATH'));
    });

    test('a project whose fvm SDK is missing says to install it', () async {
      io.File(p.join(paths[1]!, '.fvmrc')).writeAsStringSync('{"flutter":"3.24.0"}');
      flutterPath = null;
      final seen = states(1);
      await startRun(1);

      expect(started, isEmpty);
      final error = (seen.last as RunFailed).error;
      expect(error.title, 'Flutter SDK not found');
      expect(error.message, contains('pins Flutter 3.24.0 with fvm'));
      expect(error.message, contains('fvm install'));
    });

    test('the package name comes from pubspec.yaml, else from the folder name', () async {
      Future<RunError> unhandledIn(int projectId, String frame) async {
        final log = logs(projectId);
        await repository.start(
          projectId,
          device: _macos,
          mode: BuildMode.debug,
          target: 'lib/main.dart',
        );
        await pumpEventQueue();
        final process = started.last;
        await launch(process);
        for (final line in <String>[
          '[ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled Exception: Bad state: x',
          frame,
        ]) {
          await emit(process, 'app.log', <String, Object?>{'appId': 'app-1', 'log': line});
        }
        await repository.stop(projectId);
        await pumpEventQueue();
        return log.lastWhere((entry) => entry.error != null).error!;
      }

      expect(
        (await unhandledIn(1, '#0      main (package:demo_app/a.dart:2:1)')).file,
        'lib/a.dart',
      );
      paths[3] = project('folder_name');
      expect(
        (await unhandledIn(3, '#0      main (package:folder_name/b.dart:4:1)')).file,
        'lib/b.dart',
      );
    });

    test('a second start stops the first process and ignores its late events', () async {
      final seen = states(1);
      await startRun(1);
      final first = started.single;
      await launch(first);

      await startRun(1);
      expect(started, hasLength(2));
      expect(first.stopped, isTrue);
      final second = started.last;
      final afterRestart = seen.length;
      expect(seen.last, const RunBuilding());

      await emit(first, 'app.started', <String, Object?>{'appId': 'app-1'});
      first.exit(1);
      await pumpEventQueue();
      expect(seen.length, afterRestart);

      await launch(second, appId: 'app-2');
      expect(seen.last, isA<RunRunning>());
    });

    test('the runs of two projects are independent', () async {
      final one = states(1);
      final two = states(2);
      await startRun(1);
      await startRun(2);
      final first = started[0];
      final second = started[1];
      expect(second.workingDirectory, paths[2]);
      await launch(first);
      await launch(second, appId: 'app-2');

      await repository.stop(1);
      await pumpEventQueue();

      expect(first.stopped, isTrue);
      expect(second.stopped, isFalse);
      expect(one.last, const RunStopped());
      expect(two.last, isA<RunRunning>());
    });

    test('the buffer keeps the newest kRunLogLimit lines', () async {
      await startRun(1);
      final process = started.single;
      await launch(process);

      for (var i = 0; i < 2500; i++) {
        process.emit(_event('app.log', <String, Object?>{'appId': 'app-1', 'log': 'line $i'}));
      }
      await pumpEventQueue();

      final replay = logs(1);
      await pumpEventQueue();
      expect(replay, hasLength(kRunLogLimit));
      expect(replay.last.text, 'line 2499');
      expect(replay.first.text, 'line ${2500 - kRunLogLimit}');
    });

    test('markSent survives a listener that comes back', () async {
      final log = logs(1);
      await startRun(1);
      final seq = log.first.seq;

      await repository.markSent(1, seq);
      final replay = logs(1);
      await pumpEventQueue();

      expect(replay.first.sentToAgent, isTrue);
    });

    test('dispose stops every run and ends the streams', () async {
      var statesDone = false;
      var logsDone = false;
      subscriptions
        ..add(repository.watchRun(1).listen(null, onDone: () => statesDone = true))
        ..add(repository.logs(1).listen(null, onDone: () => logsDone = true));
      await startRun(1);
      await startRun(2);
      await launch(started[0]);

      await repository.dispose();
      await pumpEventQueue();

      expect(started.every((process) => process.stopped), isTrue);
      expect(statesDone, isTrue);
      expect(logsDone, isTrue);
      expect(repository.watchRun(1), emitsDone);
    });

    test('disposing twice is harmless: quitting disposes, then the app disposes again', () async {
      await startRun(1);
      await launch(started[0]);

      await repository.dispose();
      await repository.dispose();

      expect(started.single.stopped, isTrue);
      expect(repository.watchRun(1), emitsDone);
    });

    group('runtime errors from the VM service', () {
      late ScriptedVmService vm;

      setUp(() {
        vm = ScriptedVmService();
        connectErrors = (_) => FlutterErrorListener.attach(vm.service);
      });

      String projectFile(String relative) => Uri.file(p.join(paths[1]!, relative)).toString();

      List<RunError> errorsIn(List<LogEntry> log) => <RunError>[for (final e in log) ?e.error];

      /// Runs [body] and returns the warnings it logged.
      Future<List<String>> warnings(Future<void> Function() body) async {
        final logged = <String>[];
        final subscription = l.listen((event) {
          if (event.level.maybeWhen(warning: () => true, orElse: () => false)) {
            logged.add('${event.message}');
          }
        });
        try {
          await body();
        } finally {
          await subscription.cancel();
        }
        return logged;
      }

      test('connects to the VM service of a debug run after app.debugPort', () async {
        await startRun(1);
        await launch(started.single);

        expect(connectedTo, <Uri>[Uri.parse('ws://127.0.0.1:1234/abc=/ws')]);
        expect(vm.enabledIn, <String>['isolates/1']);
      });

      test('a Flutter.Error event is one error line with the project file', () async {
        final log = logs(1);
        await startRun(1);
        await launch(started.single);
        final before = log.length;

        vm.emitFlutterError(overflowFlutterError(file: projectFile('lib/main.dart')));
        await pumpEventQueue();

        final added = log.sublist(before);
        expect(added, hasLength(1));
        expect(added.single.level, LogLevel.error);
        expect(added.single.text, 'A RenderFlex overflowed by 42 pixels on the right.');
        final error = added.single.error!;
        expect(error.title, 'A RenderFlex overflowed by 42 pixels on the right.');
        expect(error.file, 'lib/main.dart');
        expect(error.line, 14);
        expect(error.location, 'main.dart:14:18');
        expect(repository.recentLogs(1).last.error, error);
      });

      test('a file under the resolved project folder is the project\'s', () async {
        final real = io.Directory(p.join(root.path, 'real'))..createSync();
        io.File(p.join(real.path, 'pubspec.yaml')).writeAsStringSync('name: demo_app\n');
        final link = io.Link(p.join(root.path, 'linked'))..createSync(real.path);
        paths[1] = link.path;
        final log = logs(1);
        await startRun(1);
        await launch(started.single);
        final before = log.length;

        final file = Uri.file(p.join(real.resolveSymbolicLinksSync(), 'lib', 'main.dart'));
        vm.emitFlutterError(overflowFlutterError(file: file.toString()));
        await pumpEventQueue();

        expect(log.sublist(before).single.error!.file, 'lib/main.dart');
      });

      test('while connected, the same error block in the output gives no second error', () async {
        final log = logs(1);
        await startRun(1);
        final process = started.single;
        await launch(process);
        final before = log.length;

        vm.emitFlutterError(overflowFlutterError(file: projectFile('lib/main.dart')));
        await pumpEventQueue();
        for (final line in overflowBlockLines(file: projectFile('lib/main.dart'))) {
          await emit(process, 'app.log', <String, Object?>{'appId': 'app-1', 'log': line});
        }

        final added = log.sublist(before);
        expect(errorsIn(added), hasLength(1));
        expect(added.length, greaterThan(1), reason: 'the block is still in the log as text');
      });

      test('a failed connect is logged once and leaves the errors to the output text', () async {
        connectErrors = (_) async => throw const io.SocketException('Connection refused');
        final log = logs(1);
        late int before;
        final logged = await warnings(() async {
          await startRun(1);
          final process = started.single;
          await launch(process);
          before = log.length;

          for (final line in overflowBlockLines(file: projectFile('lib/main.dart'))) {
            await emit(process, 'app.log', <String, Object?>{'appId': 'app-1', 'log': line});
          }
        });

        final errors = errorsIn(log.sublist(before));
        expect(errors, hasLength(1));
        expect(errors.single.title, 'Layout overflow');
        expect(repository.currentRun(1), isA<RunRunning>());
        expect(logged, hasLength(1));
        expect(logged.single, contains('Connection refused'));
      });

      test('an app without the inspector extension leaves the errors to the text', () async {
        connectErrors = (_) => FlutterErrorListener.attach(
          vm.service,
          extensionTimeout: const Duration(milliseconds: 20),
        );
        vm.isolates['isolates/1']!.clear();
        final log = logs(1);
        late int before;
        final logged = await warnings(() async {
          await startRun(1);
          final process = started.single;
          await launch(process);
          await Future<void>.delayed(const Duration(milliseconds: 40));
          await pumpEventQueue();
          before = log.length;

          for (final line in overflowBlockLines(file: projectFile('lib/main.dart'))) {
            await emit(process, 'app.log', <String, Object?>{'appId': 'app-1', 'log': line});
          }
        });

        expect(errorsIn(log.sublist(before)).single.title, 'Layout overflow');
        expect(vm.disposed, isTrue);
        expect(logged, hasLength(1));
      });

      test('profile and release runs do not connect', () async {
        await startRun(1, mode: BuildMode.profile);
        await launch(started.single);
        await startRun(2, mode: BuildMode.release);
        await launch(started.last);

        expect(connectedTo, isEmpty);
      });

      test('stop closes the connection', () async {
        await startRun(1);
        await launch(started.single);
        expect(vm.disposed, isFalse);

        await repository.stop(1);

        expect(vm.disposed, isTrue);
      });

      test('a second start closes the connection of the first', () async {
        final first = vm;
        await startRun(1);
        await launch(started.single);
        vm = ScriptedVmService();

        await startRun(1);

        expect(first.disposed, isTrue);
        expect(vm.disposed, isFalse);
      });

      test('a crash of the app closes the connection', () async {
        await startRun(1);
        final process = started.single;
        await launch(process);

        process.exit(1);
        await pumpEventQueue();

        expect(vm.disposed, isTrue);
      });

      test('dispose closes the connection', () async {
        await startRun(1);
        await launch(started.single);

        await repository.dispose();

        expect(vm.disposed, isTrue);
      });

      test('a connect that ends after the stop is closed at once', () async {
        final pending = Completer<IFlutterErrorListener>();
        connectErrors = (_) => pending.future;
        await startRun(1);
        await launch(started.single);
        await repository.stop(1);

        pending.complete(await FlutterErrorListener.attach(vm.service));
        await pumpEventQueue();

        expect(vm.disposed, isTrue);
      });

      test('a second app.debugPort does not connect again', () async {
        await startRun(1);
        final process = started.single;
        await launch(process);

        await emit(process, 'app.debugPort', <String, Object?>{
          'appId': 'app-1',
          'port': 1234,
          'wsUri': 'ws://127.0.0.1:1234/abc=/ws',
        });

        expect(connectedTo, hasLength(1));
      });
    });

    group('DevTools', () {
      /// Brings the run up with [devTools] as the `app.devTools` address (none when `null`).
      Future<ScriptedDaemonProcess> runWithDevTools(String? devTools) async {
        await startRun(1);
        final process = started.single;
        await emit(process, 'app.start', <String, Object?>{'appId': 'app-1'});
        await emit(process, 'app.debugPort', <String, Object?>{
          'appId': 'app-1',
          'wsUri': 'ws://127.0.0.1:5000/abc=/ws',
        });
        if (devTools != null) {
          await emit(process, 'app.devTools', <String, Object?>{'appId': 'app-1', 'uri': devTools});
        }
        await emit(process, 'app.started', <String, Object?>{'appId': 'app-1'});
        return process;
      }

      test('adds the VM service when the address from flutter run has none', () async {
        await runWithDevTools('http://127.0.0.1:9100');

        await repository.openDevTools(1);

        expect(opened, <Uri>[Uri.parse('http://127.0.0.1:9100/?uri=ws://127.0.0.1:5000/abc=/ws')]);
        expect(opened.single.toString(), 'http://127.0.0.1:9100/?uri=ws://127.0.0.1:5000/abc=/ws');
      });

      test('keeps other query parameters when it adds the VM service', () async {
        await runWithDevTools('http://127.0.0.1:9100/?theme=dark');

        await repository.openDevTools(1);

        expect(
          opened.single.toString(),
          'http://127.0.0.1:9100/?theme=dark&uri=ws://127.0.0.1:5000/abc=/ws',
        );
      });

      test('opens the address as it is when it already names the VM service', () async {
        const address = 'http://127.0.0.1:9100/?uri=ws://127.0.0.1:1234/other=/ws';
        await runWithDevTools(address);

        await repository.openDevTools(1);

        expect(opened, <Uri>[Uri.parse(address)]);
      });

      test('does nothing while flutter run has not reported DevTools', () async {
        await runWithDevTools(null);

        await repository.openDevTools(1);

        expect(opened, isEmpty);
      });

      test('does nothing when the app is not running', () async {
        await repository.openDevTools(1);
        await startRun(1);
        await repository.openDevTools(1);

        expect(opened, isEmpty);
      });

      test('a browser that cannot be opened is logged, not thrown', () async {
        repository = AppRunRepositoryImpl(
          projectPath: (id) async => paths[id],
          flutter: (_) => flutterPath,
          environment: const <String, String>{'PATH': '/usr/bin'},
          start: scriptedStarter(create, started: started),
          stopTimeout: const Duration(milliseconds: 50),
          openUrl: (url) async => throw const io.ProcessException('open', <String>[], 'no', 1),
          connectErrors: (uri) => connectErrors(uri),
        );
        final seen = logs(1);
        await runWithDevTools('http://127.0.0.1:9100');

        await repository.openDevTools(1);
        await pumpEventQueue();

        final failure = seen.lastWhere((log) => log.level == LogLevel.error);
        expect(failure.error?.title, 'Opening DevTools failed');
      });
    });

    group('screenshot', () {
      const pngBytes = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3];
      final png = base64Encode(pngBytes);
      const shots = '.dart_tool/flutter_code_agent/screenshots';

      /// The `app.callServiceExtension` requests the code under test sent.
      List<Map<String, Object?>> extensionCalls(ScriptedDaemonProcess process) =>
          <Map<String, Object?>>[
            for (final request in process.sent)
              if (request['method'] == 'app.callServiceExtension')
                request['params']! as Map<String, Object?>,
          ];

      /// Answers the extension calls like a debug app does; [answer] overrides one extension.
      void answerExtensions({Object? Function(String method)? answer}) {
        onRequest = (process, request) {
          final id = request['id']! as int;
          switch (request['method']) {
            case 'app.stop':
              process
                ..respond(id, result: true)
                ..exit(0);
            case 'app.callServiceExtension':
              final method = (request['params']! as Map<String, Object?>)['methodName']! as String;
              final custom = answer?.call(method);
              if (custom is DaemonError) {
                process.respond(id, error: custom.message);
              } else if (custom != null) {
                process.respond(id, result: custom);
              } else {
                process.respond(
                  id,
                  result: switch (method) {
                    'ext.flutter.inspector.getRootWidget' => <String, Object?>{
                      'result': <String, Object?>{'valueId': 'inspector-7'},
                    },
                    'ext.flutter.inspector.screenshot' => <String, Object?>{'result': png},
                    _ => <String, Object?>{'result': true},
                  },
                );
              }
          }
        };
      }

      Future<ScriptedDaemonProcess> runApp({BuildMode mode = BuildMode.debug}) async {
        await startRun(1, mode: mode);
        final process = started.single;
        await launch(process);
        return process;
      }

      test('asks the inspector for a PNG, saves it in the project and returns its path', () async {
        answerExtensions();
        final process = await runApp();

        final path = await repository.screenshot(1);

        expect(path, '$shots/screenshot-20261031-090507.png');
        expect(io.File(p.join(paths[1]!, path)).readAsBytesSync(), pngBytes);
        expect(extensionCalls(process), <Map<String, Object?>>[
          <String, Object?>{
            'appId': 'app-1',
            'methodName': 'ext.flutter.inspector.getRootWidget',
            'params': <String, Object?>{'objectGroup': 'flutter_code_agent'},
          },
          <String, Object?>{
            'appId': 'app-1',
            'methodName': 'ext.flutter.inspector.screenshot',
            'params': <String, Object?>{
              'id': 'inspector-7',
              'width': '1600',
              'height': '1600',
              'maxPixelRatio': '2',
            },
          },
          <String, Object?>{
            'appId': 'app-1',
            'methodName': 'ext.flutter.inspector.disposeGroup',
            'params': <String, Object?>{'objectGroup': 'flutter_code_agent'},
          },
        ]);
      });

      test('two shots in the same second do not overwrite each other', () async {
        answerExtensions();
        await runApp();

        final first = await repository.screenshot(1);
        final second = await repository.screenshot(1);

        expect(second, isNot(first));
        expect(io.Directory(p.join(paths[1]!, shots)).listSync(), hasLength(2));
      });

      test('keeps the 20 newest shots', () async {
        answerExtensions();
        await runApp();
        final taken = <String>[];

        for (var i = 0; i < 21; i++) {
          clock = DateTime(2026, 10, 31, 9, 5, i);
          taken.add((await repository.screenshot(1))!);
        }

        final files = io.Directory(p.join(paths[1]!, shots))
            .listSync()
            .map((e) => p.basename(e.path));
        expect(files, hasLength(20));
        expect(files, isNot(contains(p.basename(taken.first))));
        expect(files, contains(p.basename(taken.last)));
      });

      test('other files in the folder are left alone', () async {
        answerExtensions();
        await runApp();
        final folder = io.Directory(p.join(paths[1]!, shots))..createSync(recursive: true);
        io.File(p.join(folder.path, 'notes.txt')).writeAsStringSync('mine');
        for (var i = 0; i < 21; i++) {
          clock = DateTime(2026, 10, 31, 9, 5, i);
          await repository.screenshot(1);
        }

        expect(io.File(p.join(folder.path, 'notes.txt')).existsSync(), isTrue);
      });

      test('profile has no inspector: null, and nothing is asked', () async {
        answerExtensions();
        final process = await runApp(mode: BuildMode.profile);

        expect(await repository.screenshot(1), isNull);
        expect(extensionCalls(process), isEmpty);
      });

      test('null when the app is not running', () async {
        expect(await repository.screenshot(1), isNull);
        await startRun(1);
        expect(await repository.screenshot(1), isNull);
      });

      test('an error response logs "Screenshot failed" and returns null', () async {
        answerExtensions(
          answer: (method) =>
              method == 'ext.flutter.inspector.screenshot' ? const DaemonError('no render') : null,
        );
        final seen = logs(1);
        final process = await runApp();

        expect(await repository.screenshot(1), isNull);
        await pumpEventQueue();

        final failure = seen.lastWhere((log) => log.level == LogLevel.error);
        expect(failure.error?.title, 'Screenshot failed');
        expect(failure.text, startsWith('Screenshot failed'));
        expect(io.Directory(p.join(paths[1]!, shots)).existsSync(), isFalse);
        // The object group is released all the same.
        expect(extensionCalls(process).last['methodName'], 'ext.flutter.inspector.disposeGroup');
      });

      test('a null result (nothing to render) logs "Screenshot failed"', () async {
        answerExtensions(
          answer: (method) => method == 'ext.flutter.inspector.screenshot'
              ? <String, Object?>{'result': null}
              : null,
        );
        final seen = logs(1);
        await runApp();

        expect(await repository.screenshot(1), isNull);
        await pumpEventQueue();

        expect(seen.last.error?.title, 'Screenshot failed');
      });

      test('a root widget without an id logs "Screenshot failed"', () async {
        answerExtensions(
          answer: (method) => method == 'ext.flutter.inspector.getRootWidget'
              ? <String, Object?>{'result': null}
              : null,
        );
        final seen = logs(1);
        await runApp();

        expect(await repository.screenshot(1), isNull);
        await pumpEventQueue();

        expect(seen.last.error?.title, 'Screenshot failed');
      });
    });
  });
}

/// An error answer for a scripted extension call.
final class DaemonError {
  const DaemonError(this.message);

  final String message;
}
