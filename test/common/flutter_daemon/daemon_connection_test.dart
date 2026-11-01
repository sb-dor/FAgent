import 'package:flutter_code_agent/src/common/flutter_daemon/daemon_connection.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scripted_daemon_process.dart';

void main() {
  late ScriptedDaemonProcess process;
  late DaemonConnection connection;

  setUp(() {
    process = ScriptedDaemonProcess();
    connection = DaemonConnection(process);
  });

  tearDown(() => connection.close());

  test('an event frame arrives as a DaemonEvent', () async {
    final event = connection.events.first;
    process.emit(<String, Object?>{
      'event': 'daemon.connected',
      'params': <String, Object?>{'version': '0.6.1', 'pid': 1},
    });

    final received = await event;
    expect(received.name, 'daemon.connected');
    expect(received.params, <String, Object?>{'version': '0.6.1', 'pid': 1});
  });

  test('an event without params has empty params', () async {
    final event = connection.events.first;
    process.emit(<String, Object?>{'event': 'daemon.logMessage'});

    expect((await event).params, isEmpty);
  });

  test('requests get consecutive ids and are written as a protocol frame', () async {
    final first = connection.request('device.getDevices');
    final second = connection.request('app.stop', <String, Object?>{'appId': 'a'});

    expect(process.sent, <Map<String, Object?>>[
      <String, Object?>{'id': 0, 'method': 'device.getDevices', 'params': <String, Object?>{}},
      <String, Object?>{
        'id': 1,
        'method': 'app.stop',
        'params': <String, Object?>{'appId': 'a'},
      },
    ]);
    process
      ..respond(1, result: true)
      ..respond(0, result: <Object?>[]);
    expect(await second, true);
    expect(await first, <Object?>[]);
  });

  test('a response completes only the request with the same id', () async {
    var firstDone = false;
    final first = connection.request('a').whenComplete(() => firstDone = true);
    final second = connection.request('b');

    process.respond(1, result: 'second');

    expect(await second, 'second');
    expect(firstDone, isFalse);
    process.respond(0, result: 'first');
    expect(await first, 'first');
  });

  test('an error response throws DaemonRequestException', () async {
    final request = connection.request('device.getDevices');
    process.respond(0, error: 'boom');

    await expectLater(
      request,
      throwsA(
        isA<DaemonRequestException>()
            .having((e) => e.method, 'method', 'device.getDevices')
            .having((e) => e.error, 'error', 'boom'),
      ),
    );
  });

  test('lines that are not protocol frames go to output', () async {
    final lines = connection.output.take(3).toList();
    process
      ..emitLine('Waiting for another flutter command to release the startup lock...')
      ..emitLine('[not json}]')
      ..emitError('some warning');

    // stdout and stderr are separate pipes: only the order within one is fixed.
    final received = await lines;
    expect(received.where((line) => !line.isError).map((line) => line.text), <String>[
      'Waiting for another flutter command to release the startup lock...',
      '[not json}]',
    ]);
    expect(received.where((line) => line.isError).map((line) => line.text), <String>[
      'some warning',
    ]);
  });

  test('a frame with surrounding whitespace is still a frame', () async {
    final event = connection.events.first;
    process.emitLine('  [{"event":"app.log","params":{"log":"hi"}}]  ');

    expect((await event).name, 'app.log');
  });

  test('an exit with a pending request throws DaemonClosedException', () async {
    final request = connection.request('device.getDevices');
    final failure = expectLater(
      request,
      throwsA(isA<DaemonClosedException>().having((e) => e.method, 'method', 'device.getDevices')),
    );

    process.exit(1);

    await failure;
    expect(await connection.done, 1);
  });

  test('a request after the exit throws DaemonClosedException', () async {
    process.exit(0);
    await connection.done;

    await expectLater(connection.request('app.stop'), throwsA(isA<DaemonClosedException>()));
  });

  test('a response written right before the exit is not lost', () async {
    final request = connection.request('daemon.shutdown');
    process
      ..respond(0, result: 'bye')
      ..exit(0);

    expect(await request, 'bye');
  });

  test('stderr lines that arrive after the exit code and stdout end are not lost', () async {
    final lines = connection.output.toList();

    process
      ..emitError('before exit')
      ..emitLine('last stdout line')
      ..exit(1, closePipes: false)
      ..closeStdout();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    process
      ..emitError('Unhandled exception: boom')
      ..closePipes();

    expect(await connection.done, 1);
    expect(
      (await lines).map((line) => (line.text, line.isError)),
      unorderedEquals(<Object>[
        ('before exit', true),
        ('last stdout line', false),
        ('Unhandled exception: boom', true),
      ]),
    );
  });

  test('a frame of 5 MB is parsed', () async {
    final payload = 'x' * (5 * 1024 * 1024);
    final request = connection.request('app.callServiceExtension');
    process.respond(0, result: <String, Object?>{'screenshot': payload});

    final result = await request as Map<String, Object?>;
    expect((result['screenshot']! as String).length, payload.length);
  });

  test('close stops the process, fails pending requests and ends the streams', () async {
    final request = connection.request('device.getDevices');
    final failure = expectLater(request, throwsA(isA<DaemonClosedException>()));
    final eventsDone = connection.events.toList();
    final outputDone = connection.output.toList();

    await connection.close();

    expect(process.stopped, isTrue);
    await failure;
    expect(await eventsDone, isEmpty);
    expect(await outputDone, isEmpty);
    await connection.close(); // idempotent
  });

  test('a write to a dead process throws DaemonClosedException', () async {
    process.exit(0);
    // Exit is observed asynchronously: the write below happens before it.
    await expectLater(connection.request('app.stop'), throwsA(isA<DaemonClosedException>()));
  });
}
