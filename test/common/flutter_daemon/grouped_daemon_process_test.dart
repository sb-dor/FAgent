import 'dart:io';

import 'package:flutter_code_agent/src/common/flutter_daemon/daemon_connection.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/daemon_process.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

bool _isAlive(int pid) => Process.runSync('kill', <String>['-0', '$pid']).exitCode == 0;

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('grouped_daemon_process_test'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('answers a request over real stdio and stop kills the whole group', () async {
    final pidFile = File(p.join(temp.path, 'leftover.pid'));
    // A re-parented background process, then one request/response, then idle.
    final script =
        '( sleep 300 & echo \$! > "${pidFile.path}" ); '
        'read l; echo \'[{"id":0,"result":"pong"}]\'; sleep 30';
    final process = await startGroupedDaemonProcess('/bin/sh', <String>['-c', script]);
    final connection = DaemonConnection(process);

    expect(await connection.request('daemon.version'), 'pong');
    final leftover = int.parse(pidFile.readAsStringSync().trim());
    expect(_isAlive(leftover), isTrue);

    await connection.close();

    expect(_isAlive(leftover), isFalse);
  });

  test('passes the working directory and the environment through', () async {
    final process = await startGroupedDaemonProcess(
      '/bin/sh',
      <String>['-c', r'echo "$PWD|$DAEMON_TEST"'],
      workingDirectory: temp.path,
      environment: <String, String>{'DAEMON_TEST': 'yes', 'PATH': '/usr/bin:/bin'},
    );
    final connection = DaemonConnection(process);

    final line = await connection.output.first;
    expect(line.text, endsWith('|yes'));
    expect(
      Directory(line.text.split('|').first).resolveSymbolicLinksSync(),
      temp.resolveSymbolicLinksSync(),
    );
    await connection.close();
  });
}
