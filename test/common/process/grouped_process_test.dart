import 'dart:convert';
import 'dart:io';

import 'package:flutter_code_agent/src/common/process/grouped_process.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

bool _isAlive(int pid) => Process.runSync('kill', <String>['-0', '$pid']).exitCode == 0;

/// Waits until the script printed `ready`, i.e. its `trap` is installed.
Future<void> _ready(GroupedProcess process) =>
    process.stdout.transform(utf8.decoder).firstWhere((line) => line.contains('ready'));

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('grouped_process_test'));
  tearDown(() => temp.deleteSync(recursive: true));

  File script(String name, String body) {
    final file = File(p.join(temp.path, name))..writeAsStringSync('#!/bin/sh\n$body');
    Process.runSync('chmod', <String>['+x', file.path]);
    return file;
  }

  test('passes stdin, stdout, stderr and arguments through unchanged', () async {
    final echo = script('echo.sh', r'''
read line
printf '%s|%s|%s\n' "$1" "$2" "$line"
echo "to stderr" >&2
''');
    final process = await GroupedProcess.start(echo.path, <String>['a b', r'$HOME']);
    final stderr = process.stderrLines.toList();
    process.stdin.writeln('hello');
    final stdout = await process.stdout.transform(utf8.decoder).join();

    expect(stdout, 'a b|\$HOME|hello\n');
    expect(await stderr, <String>['to stderr']);
    expect(await process.exitCode, 0);
  });

  test('reports the job exit code', () async {
    final failing = script('fail.sh', 'exit 7');
    final process = await GroupedProcess.start(failing.path, const <String>[]);
    expect(await process.exitCode, 7);
  });

  // Gate from docs/M1_PLAN.md: a background process the agent started and that
  // was re-parented to launchd must not survive stopping the agent.
  test('stop kills a daemonized grandchild re-parented to launchd', () async {
    final pidFile = File(p.join(temp.path, 'grandchild.pid'));
    final agent = script('agent.sh', '''
( sleep 300 & echo \$! > "${pidFile.path}" )
read _
sleep 300
''');
    final process = await GroupedProcess.start(agent.path, const <String>[]);
    while (!pidFile.existsSync() || pidFile.readAsStringSync().trim().isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final grandchild = int.parse(pidFile.readAsStringSync().trim());
    final ppid = Process.runSync('ps', <String>['-o', 'ppid=', '-p', '$grandchild']).stdout;
    expect('$ppid'.trim(), '1', reason: 'grandchild should be re-parented to launchd');

    await process.stop(gracePeriod: const Duration(milliseconds: 500));

    expect(_isAlive(grandchild), isFalse);
    expect(process.isGroupAlive, isFalse);
  });

  test('stop escalates to SIGKILL when the job ignores SIGTERM', () async {
    final stubborn = script('stubborn.sh', '''
trap '' TERM
echo ready
while true; do sleep 1; done
''');
    final process = await GroupedProcess.start(stubborn.path, const <String>[]);
    await _ready(process);
    final stopwatch = Stopwatch()..start();
    await process.stop(
      exitAfterEof: const Duration(milliseconds: 100),
      gracePeriod: const Duration(milliseconds: 300),
    );

    expect(await process.exitCode.timeout(const Duration(seconds: 2)), isNot(0));
    expect(process.isGroupAlive, isFalse);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
  });

  test('stop waits for every group member to finish its SIGTERM handler', () async {
    final marker = File(p.join(temp.path, 'graceful.done'));
    final slow = script('slow.sh', '''
trap 'sleep 1; touch "${marker.path}"; exit 0' TERM
echo ready
while true; do sleep 0.1; done
''');
    final process = await GroupedProcess.start(slow.path, const <String>[]);
    await _ready(process);

    await process.stop(
      exitAfterEof: const Duration(milliseconds: 100),
      gracePeriod: const Duration(seconds: 3),
    );

    expect(marker.existsSync(), isTrue, reason: 'the handler should finish, not be SIGKILLed');
    expect(process.isGroupAlive, isFalse);
  });

  test('a clean exit still cleans up background leftovers', () async {
    final pidFile = File(p.join(temp.path, 'leftover.pid'));
    final agent = script(
      'leftover.sh',
      '( sleep 300 & echo \$! > "${pidFile.path}" )\nread _ || true\n',
    );
    final process = await GroupedProcess.start(agent.path, const <String>[]);
    while (!pidFile.existsSync() || pidFile.readAsStringSync().trim().isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final leftover = int.parse(pidFile.readAsStringSync().trim());

    await process.stop(gracePeriod: const Duration(milliseconds: 500));

    expect(await process.exitCode, 0);
    expect(_isAlive(leftover), isFalse);
  });
}
