import 'dart:async';
import 'dart:convert';

import 'package:flutter_code_agent/src/common/dart_analysis/lsp_connection.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scripted_lsp_process.dart';

void main() {
  late ScriptedLspProcess process;
  late LspConnection connection;

  setUp(() {
    process = ScriptedLspProcess();
    connection = LspConnection(process);
  });

  tearDown(() => connection.close());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a request gets its result by id', () async {
    process.onMessage = (process, message) => process.reply(message, <String, Object?>{'ok': 1});

    final result = await connection.request('initialize', <String, Object?>{'a': 1});

    expect(result, <String, Object?>{'ok': 1});
    expect(process.received.single['method'], 'initialize');
    expect(process.received.single['params'], <String, Object?>{'a': 1});
    expect(process.received.single['jsonrpc'], '2.0');
  });

  test('an error response throws LspRequestException with code and message', () async {
    process.onMessage = (process, message) => process.send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': message['id'],
      'error': <String, Object?>{'code': -32601, 'message': 'no such method'},
    });

    await expectLater(
      connection.request('nope', null),
      throwsA(
        isA<LspRequestException>()
            .having((e) => e.code, 'code', -32601)
            .having((e) => e.message, 'message', 'no such method'),
      ),
    );
  });

  test('a request without an answer times out', () async {
    await expectLater(
      connection.request('slow', null, timeout: const Duration(milliseconds: 20)),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('notifications arrive on the stream', () async {
    final received = <LspNotification>[];
    connection.notifications.listen(received.add);

    process.send(<String, Object?>{
      'jsonrpc': '2.0',
      'method': r'$/analyzerStatus',
      'params': <String, Object?>{'isAnalyzing': true},
    });
    await settle();

    expect(received.single.method, r'$/analyzerStatus');
    expect(received.single.params, <String, Object?>{'isAnalyzing': true});
  });

  test('a server request is answered through onServerRequest', () async {
    connection.onServerRequest = (method, params) =>
        method == 'workspace/configuration' ? <Object?>[<String, Object?>{}] : null;

    process.send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 7,
      'method': 'workspace/configuration',
      'params': <String, Object?>{},
    });
    await settle();
    await settle();

    expect(process.received.single, <String, Object?>{
      'jsonrpc': '2.0',
      'id': 7,
      'result': <Object?>[<String, Object?>{}],
    });
  });

  test('two messages in one chunk and one message split in three chunks both parse', () async {
    final received = <String>[];
    connection.notifications.listen((n) => received.add(n.method));
    List<int> note(String method) =>
        ScriptedLspProcess.frame(<String, Object?>{'jsonrpc': '2.0', 'method': method});

    process.sendRaw(<int>[...note('a'), ...note('b')]);
    final split = note('c');
    process
      ..sendRaw(split.sublist(0, 5))
      ..sendRaw(split.sublist(5, 30))
      ..sendRaw(split.sublist(30));
    await settle();

    expect(received, <String>['a', 'b', 'c']);
  });

  test('Content-Length counts UTF-8 bytes: a Cyrillic and emoji message round-trips', () async {
    const text = 'Привет 👋 мир';
    process.onMessage = (process, message) =>
        process.reply(message, (message['params']! as Map<String, Object?>)['text']);

    final result = await connection.request('echo', <String, Object?>{'text': text});

    expect(result, text);
    final written = process.writes.single;
    final header = ascii.decode(written.sublist(0, written.indexOf(13)));
    final body = utf8.encode(jsonEncode(process.received.single));
    expect(header, 'Content-Length: ${body.length}');
  });

  test('written messages carry a correct Content-Length', () {
    connection.notify('initialized', <String, Object?>{});

    final written = process.writes.single;
    final text = utf8.decode(written);
    final length = int.parse(RegExp(r'Content-Length: (\d+)').firstMatch(text)!.group(1)!);
    expect(written.length - (text.indexOf('\r\n\r\n') + 4), length);
  });

  test('after the process exits, pending and new requests fail with LspClosedException', () async {
    final pending = connection.request('waits', null);

    await process.exit();

    await expectLater(pending, throwsA(isA<LspClosedException>()));
    await expectLater(connection.request('late', null), throwsA(isA<LspClosedException>()));
    await connection.done;
  });
}
