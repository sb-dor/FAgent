import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/acp/agent_connection.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/sessions/data/sessions_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_agent_binary.dart';

AgentDefinition _fakeAs(AgentDefinition fake, String id, File requests) => AgentDefinition(
  id: id,
  displayName: id,
  executable: fake.executable,
  loginArguments: fake.loginArguments,
  environment: <String, String>{'FAKE_AGENT_REQUESTS_FILE': requests.path},
);

List<String> _methods(File requests) => requests.existsSync()
    ? <String>[
        for (final line in requests.readAsLinesSync())
          if (line.isNotEmpty) (jsonDecode(line) as Map<String, Object?>)['method']! as String,
      ]
    : const <String>[];

void main() {
  late Directory temp;
  late AgentDefinition fake;
  late ShellEnvironment environment;
  late AppDatabase database;
  late int projectId;
  late File firstRequests;
  late File secondRequests;
  late AgentHub hub;
  late SessionsRepositoryImpl repository;

  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('sessions_repository_test');
    fake = await compileFakeAgent(temp);
    environment = await ShellEnvironment.resolve();
  });

  tearDownAll(() => temp.deleteSync(recursive: true));

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    projectId = await database
        .into(database.projectsTable)
        .insert(ProjectsTableCompanion.insert(path: temp.path, name: 'project'));
    firstRequests = File('${temp.path}/first_requests.jsonl');
    secondRequests = File('${temp.path}/second_requests.jsonl');
    for (final file in <File>[firstRequests, secondRequests]) {
      if (file.existsSync()) file.deleteSync();
    }
    hub = AgentHub(
      database: database,
      environment: environment,
      agents: <String, AgentDefinition>{
        'first': _fakeAs(fake, 'first', firstRequests),
        'second': _fakeAs(fake, 'second', secondRequests),
      },
      connector: (definition, onPermission) => AgentConnection.start(
        definition: definition,
        environment: environment,
        onPermissionRequest: onPermission,
        initializeTimeout: const Duration(seconds: 20),
      ),
      cancelTimeout: const Duration(seconds: 1),
    );
    repository = SessionsRepositoryImpl(database: database, hub: hub);
  });

  tearDown(() async {
    await hub.dispose();
    await database.close();
  });

  Future<int> newChat({String agentId = 'first', String? acpSessionId}) => database
      .into(database.sessionsTable)
      .insert(
        SessionsTableCompanion.insert(
          projectId: projectId,
          agentId: agentId,
          acpSessionId: Value(acpSessionId),
        ),
      );

  Future<String> agentOf(int id) async => (await (database.select(
    database.sessionsTable,
  )..where((s) => s.id.equals(id))).getSingle()).agentId;

  test("setAgent changes a new chat's agent", () async {
    final chat = await newChat();

    await repository.setAgent(chat, 'second');

    expect(await agentOf(chat), 'second');
  });

  test('setAgent refuses after the first message', () async {
    final chat = await newChat(acpSessionId: 'acp-1');

    await expectLater(repository.setAgent(chat, 'second'), throwsStateError);

    expect(await agentOf(chat), 'first');
  });

  test('setAgent drops the cached chat so the next open reads the new agent', () async {
    final chat = await newChat();
    final before = await hub.session(chat);
    expect(before.agentId, 'first');

    await repository.setAgent(chat, 'second');

    expect(hub.opened(chat), isNull);
    final after = await hub.session(chat);
    expect(after.agentId, 'second');
    expect(identical(after, before), isFalse);
  });

  test(
    'switching agent after the hub opened the chat sends the first prompt to the new agent',
    () async {
      final chat = await newChat();
      final live = await hub.session(chat);
      expect(live.agentId, 'first');
      expect(live.status.value, SessionStatus.cold);

      await repository.setAgent(chat, 'second');
      await hub.prompt(chat, 'echo hello');

      expect(_methods(secondRequests), <String>['session/new']);
      expect(_methods(firstRequests), isEmpty);
      expect((await hub.session(chat)).agentId, 'second');
    },
  );

  test('forget disposes the dropped runtime state', () async {
    final chat = await newChat();
    final live = await hub.session(chat);

    expect(await hub.forget(chat), isTrue);

    // A disposed notifier refuses new listeners.
    expect(() => live.status.addListener(() {}), throwsFlutterError);
  });

  test('a chat that is running is not dropped by forget', () async {
    final chat = await newChat();
    final live = await hub.session(chat);
    final prompt = hub.prompt(chat, 'hang');
    await _untilStatus(live, SessionStatus.running);

    await hub.forget(chat);

    expect(hub.opened(chat), same(live));
    await hub.cancel(chat);
    await prompt.catchError((Object _) {});
  });

  test('setAgent refuses while the first prompt is starting the agent', () async {
    final chat = await newChat();
    final live = await hub.session(chat);
    var changeableWhileStarting = true;
    live.status.addListener(() {
      if (live.status.value == SessionStatus.starting) {
        changeableWhileStarting = hub.canChangeAgent(chat);
      }
    });
    final prompt = hub.prompt(chat, 'hang');
    await _untilStatus(live, SessionStatus.running);

    // The row has no agent session in the first moments, only the hub knows the chat is busy.
    expect(changeableWhileStarting, isFalse);
    await expectLater(repository.setAgent(chat, 'second'), throwsStateError);

    expect(await agentOf(chat), 'first');
    expect(hub.opened(chat), same(live));
    expect(_methods(secondRequests), isEmpty);
    await hub.cancel(chat);
    await prompt.catchError((Object _) {});
  });

  test('setAgent refuses while the agent session is being created', () async {
    final chat = await newChat();
    await hub.session(chat);
    final prompt = hub.prompt(chat, 'echo hi');
    // The prompt is in its setup lane before the agent has started.
    await Future<void>.delayed(Duration.zero);
    expect(hub.canChangeAgent(chat), isFalse);

    await expectLater(repository.setAgent(chat, 'second'), throwsStateError);
    await prompt;

    expect(await agentOf(chat), 'first');
    expect(_methods(secondRequests), isEmpty);
    expect(_methods(firstRequests), <String>['session/new']);
  });

  test('a chat waiting for a sign-in can change its agent', () async {
    final chat = await newChat();
    final live = await hub.session(chat);
    live
      ..problem.value = const SessionProblem(SessionProblemKind.auth, 'Authentication required')
      ..status.value = SessionStatus.needsAuth;

    await repository.setAgent(chat, 'second');

    expect(await agentOf(chat), 'second');
    expect(hub.opened(chat), isNull);
  });

  test('a chat of a removed agent can be moved to a live one', () async {
    final chat = await newChat(agentId: 'gone');
    final live = await hub.session(chat);
    expect(live.status.value, SessionStatus.error);
    expect(live.problem.value?.kind, SessionProblemKind.removed);

    await repository.setAgent(chat, 'second');

    final after = await hub.session(chat);
    expect(after.agentId, 'second');
    expect(after.status.value, SessionStatus.cold);
  });
}

Future<void> _untilStatus(LiveSession live, SessionStatus status) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (live.status.value != status) {
    if (DateTime.now().isAfter(deadline)) throw StateError('never reached ${status.name}');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
