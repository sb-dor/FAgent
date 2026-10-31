@Tags(<String>['flutter'])
library;

import 'dart:async';
import 'dart:io' as io;

import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_executable.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Runs the real `flutter run --machine` on macOS against an app it creates in a temp folder:
/// build, a hot reload that fails to compile, the fix, a hot reload that works, and the stop.
///
/// Opt-in: `FLUTTER_RUN_TEST=1 flutter test test/integration/flutter_run_test.dart`.
void main() {
  final enabled = io.Platform.environment['FLUTTER_RUN_TEST'] == '1';

  test(
    'flutter run on macOS: run, a failing reload, a fixed reload, stop',
    () async {
      final environment = ShellEnvironment(Map<String, String>.of(io.Platform.environment));
      final root = io.Directory.systemTemp.createTempSync('flutter_run_test');
      addTearDown(() => root.deleteSync(recursive: true));
      final flutter = flutterExecutableFor(null, which: environment.which);
      expect(flutter, isNotNull, reason: 'flutter is not on the PATH');

      final project = p.join(root.path, 'run_probe');
      final created = await io.Process.run(flutter!, <String>[
        'create',
        '--platforms=macos',
        '--project-name',
        'run_probe',
        project,
      ], environment: environment.variables);
      expect(created.exitCode, 0, reason: '${created.stdout}\n${created.stderr}');

      final repository = AppRunRepositoryImpl(
        projectPath: (_) async => project,
        flutter: (_) => flutter,
        environment: environment.variables,
      );
      addTearDown(repository.dispose);
      final states = <RunState>[];
      final logs = <LogEntry>[];
      final subscriptions = <StreamSubscription<Object?>>[
        repository.watchRun(1).listen(states.add),
        repository.logs(1).listen(logs.add),
      ];
      addTearDown(() async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      });
      String output() => logs.map((entry) => entry.text).join('\n');

      Future<void> until(bool Function() condition, Duration timeout, String what) async {
        final deadline = DateTime.now().add(timeout);
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) fail('Timed out waiting for $what.\n${output()}');
          if (states.lastOrNull is RunFailed) fail('The run failed: ${states.last}\n${output()}');
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }

      final stopwatch = Stopwatch()..start();
      await repository.start(
        1,
        device: const Device(
          id: 'macos',
          name: 'macOS',
          platform: DevicePlatform.macos,
          kind: DeviceKind.running,
        ),
        mode: BuildMode.debug,
        target: 'lib/main.dart',
      );
      await until(
        () => states.lastOrNull is RunRunning,
        const Duration(minutes: 5),
        'the app to run',
      );
      // ignore: avoid_print
      print('flutter run: running after ${stopwatch.elapsed}');
      final running = states.last as RunRunning;
      expect(running.vmServiceUri, isNotNull);
      final group = await _groupOf(p.join(project, 'build'));
      expect(group, isNotNull, reason: 'the app process was not found');

      final main = io.File(p.join(project, 'lib', 'main.dart'));
      final source = main.readAsStringSync();
      main.writeAsStringSync('$source\nvoid broken() {\n  final int x = ;\n}\n');
      expect(await repository.hotReload(1), Duration.zero);
      final failedAt = DateTime.now();
      bool failureLogged() =>
          logs.any((entry) => entry.error?.title == 'Hot reload failed') &&
          logs.any(
            (entry) =>
                entry.error?.title == 'Compilation error' && entry.error?.file == 'lib/main.dart',
          );
      while (!failureLogged() &&
          DateTime.now().difference(failedAt) < const Duration(seconds: 30)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(failureLogged(), isTrue, reason: output());
      expect(states.last, isA<RunRunning>());

      main.writeAsStringSync(source);
      final took = await repository.hotReload(1);
      expect(took, greaterThan(Duration.zero), reason: output());
      await until(
        () => states.last is RunRunning && (states.last as RunRunning).lastReload == took,
        const Duration(seconds: 5),
        'the reload time in the state',
      );

      await repository.stop(1);
      await until(
        () => states.last == const RunStopped(),
        const Duration(seconds: 5),
        'the stopped state',
      );
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (await _groupAlive(group!) && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(await _groupAlive(group), isFalse, reason: 'process group $group is still alive');
      // ignore: avoid_print
      print('flutter run: whole test took ${stopwatch.elapsed}');
    },
    skip: enabled ? false : 'Runs the real flutter on macOS; set FLUTTER_RUN_TEST=1',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

/// The process group of the running app: the process whose command lies under [buildDir].
Future<int?> _groupOf(String buildDir) async {
  for (final (:pgid, :command) in await _processes()) {
    if (command.contains(buildDir)) return pgid;
  }
  return null;
}

Future<bool> _groupAlive(int pgid) async =>
    (await _processes()).any((process) => process.pgid == pgid);

Future<List<({int pgid, String command})>> _processes() async {
  final result = await io.Process.run('ps', <String>['-axo', 'pgid=,command=']);
  final out = <({int pgid, String command})>[];
  for (final line in (result.stdout as String).split('\n')) {
    final match = RegExp(r'^\s*(\d+)\s+(.*)$').firstMatch(line);
    if (match != null) out.add((pgid: int.parse(match.group(1)!), command: match.group(2)!));
  }
  return out;
}
