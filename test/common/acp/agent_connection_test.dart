import 'dart:async';
import 'dart:io';

import 'package:dart_acp_sdk/dart_acp_sdk.dart';
import 'package:flutter_code_agent/src/common/acp/agent_connection.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_preflight.dart';
import 'package:flutter_code_agent/src/common/acp/raw_acp_message.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/fake_agent_binary.dart';

Future<RequestPermissionResponse> _allow(
  AcpClientRequestContext<RequestPermissionRequest> context,
) async => RequestPermissionResponse(
  outcome: RequestPermissionOutcomeSelected(
    SelectedPermissionOutcome(optionId: PermissionOptionId('allow')),
  ),
);

List<String> _agentText(List<RawAcpMessage> messages, String sessionId) => <String>[
  for (final message in messages)
    if (message.method == 'session/update' && message.sessionId == sessionId)
      if (message.params?['update'] case {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'text': final String text},
      })
        text,
];

void main() {
  late Directory temp;
  late AgentDefinition fakeAgent;
  late ShellEnvironment environment;

  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('agent_connection_test');
    fakeAgent = await compileFakeAgent(
      temp,
      environment: <String, String>{'FAKE_AGENT_PID_FILE': p.join(temp.path, 'spawned.pid')},
    );
    environment = await ShellEnvironment.resolve();
  });

  tearDownAll(() => temp.deleteSync(recursive: true));

  Future<AgentConnection> start({AgentPermissionHandler onPermissionRequest = _allow}) =>
      AgentConnection.start(
        definition: fakeAgent,
        environment: environment,
        onPermissionRequest: onPermissionRequest,
        initializeTimeout: const Duration(seconds: 20),
      );

  Future<SessionId> newSession(AgentConnection connection) async =>
      (await connection.agent.createSession(
        NewSessionRequest(cwd: temp.path, mcpServers: const <McpServer>[]),
      )).sessionId;

  PromptRequest prompt(SessionId session, String text) => PromptRequest(
    sessionId: session,
    prompt: <ContentBlock>[ContentBlockText(TextContent(text: text))],
  );

  test('publishes raw messages before the SDK decodes them', () async {
    final connection = await start();
    addTearDown(connection.close);
    final messages = <RawAcpMessage>[];
    connection.incoming.listen(messages.add);

    final session = await newSession(connection);
    final response = await connection.agent.sendPrompt(prompt(session, 'echo hello world'));

    expect(response.stopReason, StopReason.endTurn);
    expect(_agentText(messages, session.value).join(), 'hello world');
    final chunk = messages.firstWhere((m) => m.method == 'session/update');
    expect(chunk.isNotification, isTrue);
    expect(chunk.params?['update'], containsPair('messageId', 'm1'));
  });

  test('routes permission requests to the handler and returns its answer', () async {
    final requests = <RequestPermissionRequest>[];
    final connection = await start(
      onPermissionRequest: (context) {
        requests.add(context.params);
        return _allow(context);
      },
    );
    addTearDown(connection.close);
    final messages = <RawAcpMessage>[];
    connection.incoming.listen(messages.add);

    final session = await newSession(connection);
    await connection.agent.sendPrompt(prompt(session, 'permission'));

    expect(requests.single.options.map((o) => o.optionId.value), <String>['allow', 'reject']);
    expect(messages.where((m) => m.isRequest).single.method, 'session/request_permission');
    expect(_agentText(messages, session.value), <String>['allow']);
  });

  test('cancel ends a hanging turn with stopReason cancelled', () async {
    final connection = await start();
    addTearDown(connection.close);
    final session = await newSession(connection);

    final turn = connection.agent.sendPrompt(prompt(session, 'hang'));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await connection.agent.cancelSession(CancelNotification(sessionId: session));

    expect((await turn.timeout(const Duration(seconds: 5))).stopReason, StopReason.cancelled);
  });

  test('surfaces authRequired as a JSON-RPC error with code -32000', () async {
    final connection = await start();
    addTearDown(connection.close);
    final session = await newSession(connection);

    await expectLater(
      connection.agent.sendPrompt(prompt(session, 'auth')),
      throwsA(isA<JsonRpcRequestException>().having((e) => e.error.code, 'code', -32000)),
    );
  });

  test('keeps the stderr tail', () async {
    final connection = await start();
    addTearDown(connection.close);
    final session = await newSession(connection);

    await connection.agent.sendPrompt(prompt(session, 'stderr something broke'));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(connection.stderrTail, contains('something broke'));
  });

  test('reports a crash through exitCode and closes incoming', () async {
    final connection = await start();
    final session = await newSession(connection);
    final incomingDone = connection.incoming.drain<void>();

    unawaited(connection.agent.sendPrompt(prompt(session, 'crash')).then((_) {}, onError: (_) {}));

    expect(await connection.exitCode.timeout(const Duration(seconds: 5)), 3);
    await incomingDone.timeout(const Duration(seconds: 5));
    await connection.close();
  });

  test('close stops background processes the agent left behind', () async {
    final connection = await start();
    final session = await newSession(connection);
    await connection.agent.sendPrompt(prompt(session, 'spawn'));
    final pid = int.parse(File(p.join(temp.path, 'spawned.pid')).readAsStringSync().trim());
    expect(Process.runSync('kill', <String>['-0', '$pid']).exitCode, 0);

    await connection.close(gracePeriod: const Duration(seconds: 1));

    expect(Process.runSync('kill', <String>['-0', '$pid']).exitCode, isNot(0));
  });

  test('fails with AgentStartException when initialize never answers', () async {
    const silent = AgentDefinition(
      id: 'silent',
      displayName: 'Silent',
      executable: '/bin/sleep',
      arguments: <String>['30'],
    );
    await expectLater(
      AgentConnection.start(
        definition: silent,
        environment: environment,
        onPermissionRequest: _allow,
        initializeTimeout: const Duration(milliseconds: 500),
      ),
      throwsA(isA<AgentStartException>()),
    );
  });

  group('preflight', () {
    test('rejects a missing executable', () async {
      const missing = AgentDefinition(
        id: 'x',
        displayName: 'X',
        executable: 'no-such-agent-binary',
      );
      await expectLater(
        AgentPreflight.check(missing, environment),
        throwsA(isA<AgentPreflightException>()),
      );
    });

    test('rejects a Node.js older than required', () async {
      const future = AgentDefinition(
        id: 'x',
        displayName: 'X',
        executable: 'npx',
        minimumNodeMajor: 999,
      );
      await expectLater(
        AgentPreflight.check(future, environment),
        throwsA(
          isA<AgentPreflightException>().having((e) => e.message, 'message', contains('999')),
        ),
      );
    });
  });
}
