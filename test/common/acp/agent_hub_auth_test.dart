import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_acp_sdk/dart_acp_sdk.dart' as acp;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/acp/agent_connection.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_agent_binary.dart';

/// Completes when [notifier] reaches a value matching [test].
Future<void> _until<T>(ValueListenable<T> notifier, bool Function(T value) test) {
  if (test(notifier.value)) return Future<void>.value();
  final done = Completer<void>();
  void listener() {
    if (test(notifier.value) && !done.isCompleted) done.complete();
  }

  notifier.addListener(listener);
  return done.future
      .timeout(const Duration(seconds: 15))
      .whenComplete(() => notifier.removeListener(listener));
}

Future<void> _poll(bool Function() test, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!test()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException(what);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

List<String> _agentText(LiveSession live) => <String>[
  for (final event in live.store.events)
    if (event.kind == 'agent_message_chunk')
      if (event.payload case {'params': {'update': {'content': {'text': final String text}}}}) text,
];

void main() {
  late Directory temp;
  late AgentDefinition compiled;
  late ShellEnvironment environment;
  late AppDatabase database;
  late int projectId;
  late File requests;
  late List<AgentConnection> connections;
  final hubs = <AgentHub>[];

  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('agent_hub_auth_test');
    compiled = await compileFakeAgent(temp);
    environment = await ShellEnvironment.resolve();
  });

  tearDownAll(() => temp.deleteSync(recursive: true));

  setUp(() async {
    connections = <AgentConnection>[];
    requests = File('${temp.path}/requests-${DateTime.now().microsecondsSinceEpoch}.jsonl');
    database = AppDatabase(NativeDatabase.memory());
    projectId = await database
        .into(database.projectsTable)
        .insert(ProjectsTableCompanion.insert(path: temp.path, name: 'project'));
  });

  tearDown(() async {
    for (final hub in hubs) {
      await hub.dispose();
    }
    hubs.clear();
    await database.close();
  });

  AgentHub newHub({Map<String, String> agentEnvironment = const <String, String>{}}) {
    final agent = AgentDefinition(
      id: 'fake',
      displayName: compiled.displayName,
      executable: compiled.executable,
      loginArguments: compiled.loginArguments,
      environment: <String, String>{'FAKE_AGENT_REQUESTS_FILE': requests.path, ...agentEnvironment},
    );
    final hub = AgentHub(
      database: database,
      environment: environment,
      agents: <String, AgentDefinition>{'fake': agent},
      connector: (definition, onPermission) async {
        final connection = await AgentConnection.start(
          definition: definition,
          environment: environment,
          onPermissionRequest: onPermission,
          initializeTimeout: const Duration(seconds: 20),
        );
        connections.add(connection);
        return connection;
      },
      cancelTimeout: const Duration(seconds: 1),
    );
    hubs.add(hub);
    return hub;
  }

  Future<int> newChat() => database
      .into(database.sessionsTable)
      .insert(SessionsTableCompanion.insert(projectId: projectId, agentId: 'fake'));

  List<Map<String, Object?>> recorded() => !requests.existsSync()
      ? const <Map<String, Object?>>[]
      : <Map<String, Object?>>[
          for (final line in requests.readAsLinesSync())
            if (line.isNotEmpty) jsonDecode(line) as Map<String, Object?>,
        ];

  test('authenticate succeeds and retries needsAuth chats', () async {
    final hub = newHub();
    final chat = await newChat();
    final live = await hub.session(chat);
    await hub.prompt(chat, 'auth');
    expect(live.status.value, SessionStatus.needsAuth);

    await hub.authenticate('fake', 'browser-login');

    await _until(live.status, (s) => s == SessionStatus.cold);
    expect(live.problem.value, isNull);
    expect(live.canRetryPrompt.value, isTrue);
    expect(
      recorded().where((r) => r['method'] == 'authenticate').map((r) => r['params']),
      <Object?>[
        <String, Object?>{'methodId': 'browser-login'},
      ],
    );
    await hub.retryPrompt(chat);
    expect(_agentText(live), <String>['authenticated']);
    expect(connections, hasLength(1), reason: 'the signed-in connection is kept');
  });

  test('the client advertises terminal auth and the auth status extension', () async {
    final hub = newHub();

    await hub.authenticate('fake', 'api-key');

    final capabilities = recorded().singleWhere((r) => r['method'] == 'client/capabilities');
    expect(capabilities['params'], <String, Object?>{
      'capabilities': <String, Object?>{
        'clientCapabilities': containsPair('_meta', <String, Object?>{
          'terminal-auth': true,
          'authStatus': <String, Object?>{},
        }),
      },
    });
  });

  test('authenticate failure propagates and leaves needsAuth', () async {
    final hub = newHub(agentEnvironment: const <String, String>{'FAKE_AGENT_AUTH_FAIL': '1'});
    final chat = await newChat();
    final live = await hub.session(chat);
    await hub.prompt(chat, 'auth');

    await expectLater(
      hub.authenticate('fake', 'browser-login'),
      throwsA(isA<acp.JsonRpcRequestException>()),
    );

    expect(live.status.value, SessionStatus.needsAuth);
    expect(live.problem.value?.kind, SessionProblemKind.auth);
    expect(connections.single.isAlive, isTrue);
  });

  test('cancelled authenticate closes the connection', () async {
    final hub = newHub(agentEnvironment: const <String, String>{'FAKE_AGENT_AUTH_HANG': '1'});
    final chat = await newChat();
    final live = await hub.session(chat);
    await hub.prompt(chat, 'auth');
    final source = acp.CancellationSource();

    final signIn = hub.authenticate('fake', 'browser-login', cancel: source.token);
    await _poll(
      () => recorded().any((r) => r['method'] == 'authenticate'),
      'authenticate was not sent',
    );
    source.cancel();

    await expectLater(signIn, throwsA(isA<acp.CancellationException>()));
    await connections.single.exitCode.timeout(const Duration(seconds: 10));
    expect(hub.initializeResultOf('fake'), isNull);
    expect(live.status.value, SessionStatus.needsAuth, reason: 'the chat still waits for a login');
  });

  test('logout sends logout and closes', () async {
    final hub = newHub();
    final chat = await newChat();
    final live = await hub.session(chat);
    await hub.prompt(chat, 'echo hi');

    await hub.logout('fake');

    expect(recorded().map((r) => r['method']), contains('logout'));
    await connections.single.exitCode.timeout(const Duration(seconds: 10));
    expect(hub.initializeResultOf('fake'), isNull);
    expect(live.status.value, SessionStatus.cold);
  });

  test('initializeResultOf returns agentCapabilities after a chat started', () async {
    final hub = newHub();
    expect(hub.initializeResultOf('fake'), isNull);
    expect(hub.initializeResultOf('unknown'), isNull);
    final chat = await newChat();
    await hub.prompt(chat, 'echo hi');

    final result = hub.initializeResultOf('fake');

    expect(result?['agentCapabilities'], containsPair('loadSession', true));
    expect(result?['authMethods'], <Object?>[
      <String, Object?>{'id': 'browser-login', 'name': 'Browser login'},
      <String, Object?>{
        'id': 'api-key',
        'name': 'API key',
        '_meta': <String, Object?>{
          'api-key': <String, Object?>{'provider': 'fake'},
        },
      },
    ]);
  });

  test('authenticate of an unknown agent throws', () async {
    final hub = newHub();

    await expectLater(hub.authenticate('nobody', 'browser-login'), throwsStateError);
    await expectLater(hub.logout('nobody'), throwsStateError);
  });
}
