import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/acp/agent_connection.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/session_event.dart';
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

/// Waits until the prompt of the current turn is journaled and sent.
Future<void> _untilSent(LiveSession live) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!live.store.events.any((e) => e.kind == SessionEventKind.prompt)) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('prompt was not sent');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await Future<void>.delayed(const Duration(milliseconds: 100));
}

List<String> _agentText(LiveSession live) => <String>[
  for (final event in live.store.events)
    if (event.kind == 'agent_message_chunk')
      if (event.payload case {'params': {'update': {'content': {'text': final String text}}}}) text,
];

void main() {
  late Directory temp;
  late AgentDefinition fakeAgent;
  late ShellEnvironment environment;
  late AppDatabase database;
  late int projectId;
  late List<AgentConnection> connections;
  final hubs = <AgentHub>[];

  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('agent_hub_agents_test');
    fakeAgent = await compileFakeAgent(temp);
    environment = await ShellEnvironment.resolve();
  });

  tearDownAll(() => temp.deleteSync(recursive: true));

  setUp(() async {
    connections = <AgentConnection>[];
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

  AgentHub newHub({Map<String, AgentDefinition>? agents}) {
    final hub = AgentHub(
      database: database,
      environment: environment,
      agents: agents ?? <String, AgentDefinition>{'fake': fakeAgent},
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

  Future<int> newChat({String agentId = 'fake'}) => database
      .into(database.sessionsTable)
      .insert(SessionsTableCompanion.insert(projectId: projectId, agentId: agentId));

  AgentDefinition edited(AgentDefinition agent, Map<String, String> environment) => AgentDefinition(
    id: agent.id,
    displayName: agent.displayName,
    executable: agent.executable,
    loginArguments: agent.loginArguments,
    environment: environment,
    source: AgentSource.custom,
  );

  test('setAgents adds a slot that can run a chat', () async {
    final hub = newHub(agents: const <String, AgentDefinition>{})
      ..setAgents(<AgentDefinition>[fakeAgent]);
    expect(hub.agents, <AgentDefinition>[fakeAgent]);
    final chat = await newChat();
    final live = await hub.session(chat);

    await hub.prompt(chat, 'echo hello');

    expect(_agentText(live).join(), 'hello');
    expect(live.status.value, SessionStatus.idle);
  });

  test('an equal definition changes nothing', () async {
    final hub = newHub();
    final chat = await newChat();
    final live = await hub.session(chat);
    await hub.prompt(chat, 'echo one');

    // A new but equal instance, as the custom agents stream emits on every change.
    hub.setAgents(<AgentDefinition>[
      AgentDefinition(
        id: fakeAgent.id,
        displayName: fakeAgent.displayName,
        executable: fakeAgent.executable,
        loginArguments: fakeAgent.loginArguments,
      ),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(connections.single.isAlive, isTrue);
    expect(live.status.value, SessionStatus.idle);
  });

  test('editing an idle agent restarts it at once', () async {
    final hub = newHub();
    final chat = await newChat();
    final live = await hub.session(chat);
    await hub.prompt(chat, 'echo one');
    final first = connections.single;

    hub.setAgents(<AgentDefinition>[
      edited(fakeAgent, const <String, String>{'EDITED': '1'}),
    ]);

    await first.exitCode.timeout(const Duration(seconds: 10));
    expect(live.status.value, SessionStatus.cold);
    await hub.prompt(chat, 'echo two');
    expect(connections, hasLength(2));
    expect(connections.last.definition.environment, <String, String>{'EDITED': '1'});
  });

  test('edit while a turn runs restarts only after the turn', () async {
    final hub = newHub();
    final busy = await newChat();
    final idle = await newChat();
    final busyLive = await hub.session(busy);
    final idleLive = await hub.session(idle);
    await hub.prompt(idle, 'echo ready');
    final turn = hub.prompt(busy, 'hang');
    await _untilSent(busyLive);
    final first = connections.single;

    hub.setAgents(<AgentDefinition>[
      edited(fakeAgent, const <String, String>{'EDITED': '1'}),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(first.isAlive, isTrue, reason: 'the running turn keeps its process');
    expect(busyLive.status.value, SessionStatus.running);
    expect(idleLive.status.value, SessionStatus.idle);

    await hub.cancel(busy);
    await turn;
    await first.exitCode.timeout(const Duration(seconds: 10));
    await _until(busyLive.status, (s) => s == SessionStatus.cold);
    expect(busyLive.problem.value, isNull, reason: 'the turn ended normally');
    expect(idleLive.status.value, SessionStatus.cold);

    await hub.prompt(busy, 'echo again');
    expect(connections, hasLength(2));
    expect(connections.last.definition.environment, <String, String>{'EDITED': '1'});
  });

  test('remove closes the process and marks its chats removed', () async {
    final hub = newHub();
    final chat = await newChat();
    final waiting = await newChat();
    final live = await hub.session(chat);
    final waitingLive = await hub.session(waiting);
    await hub.prompt(chat, 'echo hi');
    await hub.prompt(waiting, 'auth');
    expect(waitingLive.status.value, SessionStatus.needsAuth);
    final first = connections.single;

    hub.setAgents(const <AgentDefinition>[]);

    await first.exitCode.timeout(const Duration(seconds: 10));
    expect(hub.agents, isEmpty);
    for (final removed in <LiveSession>[live, waitingLive]) {
      await _until(removed.status, (s) => s == SessionStatus.error);
      expect(removed.problem.value?.kind, SessionProblemKind.removed);
      expect(removed.problem.value?.message, 'This agent was removed');
    }
    await expectLater(hub.prompt(chat, 'echo again'), throwsA(isA<AgentRemovedException>()));
    await expectLater(hub.retry(chat), throwsA(isA<AgentRemovedException>()));
    expect(live.status.value, SessionStatus.error);
    expect(live.problem.value?.message, 'This agent was removed');
    expect(connections, hasLength(1), reason: 'nothing starts for a removed agent');
  });

  test('opening a chat of an unknown agent gives the removed problem, not a StateError', () async {
    final hub = newHub();
    final chat = await newChat(agentId: 'custom:7');

    final live = await hub.session(chat);

    expect(live.status.value, SessionStatus.error);
    expect(live.problem.value?.kind, SessionProblemKind.removed);
    expect(live.problem.value?.message, 'This agent was removed');
    expect(live.canRetryPrompt.value, isFalse);
    await expectLater(hub.prompt(chat, 'echo hi'), throwsA(isA<AgentRemovedException>()));
    expect(connections, isEmpty);
  });

  test('a removed agent that comes back can run its chats again', () async {
    final hub = newHub()..setAgents(const <AgentDefinition>[]);
    final chat = await newChat();
    final live = await hub.session(chat);
    expect(live.problem.value?.kind, SessionProblemKind.removed);

    hub.setAgents(<AgentDefinition>[fakeAgent]);
    await hub.prompt(chat, 'echo back');

    expect(_agentText(live).join(), 'back');
  });

  test('a chat of an agent removed while it starts does not leave a process behind', () async {
    final hub = newHub();
    final chat = await newChat();
    final live = await hub.session(chat);
    final prompt = hub.prompt(chat, 'echo hi');
    await _until(live.status, (s) => s == SessionStatus.starting);

    hub.setAgents(const <AgentDefinition>[]);

    await expectLater(prompt, throwsA(anything));
    expect(live.status.value, SessionStatus.error);
    expect(live.problem.value?.kind, SessionProblemKind.removed);
    for (final connection in connections) {
      await connection.exitCode.timeout(const Duration(seconds: 10));
    }
  });
}
