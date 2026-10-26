import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
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

/// Waits until the prompt of the current turn is journaled and sent (`running`
/// is set earlier, when the turn is reserved).
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
  final hubs = <AgentHub>[];

  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('agent_hub_test');
    fakeAgent = await compileFakeAgent(
      temp,
      environment: <String, String>{'FAKE_AGENT_PID_FILE': '${temp.path}/spawned.pid'},
    );
    environment = await ShellEnvironment.resolve();
  });

  tearDownAll(() => temp.deleteSync(recursive: true));

  setUp(() async {
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

  AgentHub newHub({List<TurnObserver> observers = const <TurnObserver>[]}) {
    final hub = AgentHub(
      observers: observers,
      database: database,
      environment: environment,
      agents: <String, AgentDefinition>{'fake': fakeAgent},
      connector: (definition, onPermission) => AgentConnection.start(
        definition: definition,
        environment: environment,
        onPermissionRequest: onPermission,
        initializeTimeout: const Duration(seconds: 20),
      ),
      cancelTimeout: const Duration(seconds: 1),
    );
    hubs.add(hub);
    return hub;
  }

  Future<int> newChat({String? acpSessionId}) => database
      .into(database.sessionsTable)
      .insert(
        SessionsTableCompanion.insert(
          projectId: projectId,
          agentId: 'fake',
          acpSessionId: acpSessionId == null
              ? const Value<String?>.absent()
              : Value<String?>(acpSessionId),
        ),
      );

  test('the first prompt creates the agent session and journals the turn', () async {
    final hub = newHub();
    final chat = await newChat();
    final live = await hub.session(chat);
    final statuses = <SessionStatus>[];
    live.status.addListener(() => statuses.add(live.status.value));

    await hub.prompt(chat, 'echo hello world');

    expect(statuses, <SessionStatus>[
      SessionStatus.starting,
      SessionStatus.creating,
      SessionStatus.idle,
      SessionStatus.running,
      SessionStatus.idle,
    ]);
    final record = await (database.select(
      database.sessionsTable,
    )..where((s) => s.id.equals(chat))).getSingle();
    expect(record.acpSessionId, live.acpSessionId);
    expect(record.title, 'echo hello world');
    expect(live.store.events.first.kind, SessionEventKind.prompt);
    expect(_agentText(live).join(), 'hello world');
    expect(live.store.events.last.payload, containsPair('stopReason', 'end_turn'));
  });

  test('a config option change returns the agent\'s new options', () async {
    final hub = newHub();
    final chat = await newChat();
    final live = await hub.session(chat);
    await hub.prompt(chat, 'echo hi');
    expect(live.configOptions.value.single, containsPair('currentValue', 'default'));

    await hub.setConfigOption(chat, 'mode', 'acceptEdits');

    expect(live.configOptions.value.single, containsPair('currentValue', 'acceptEdits'));
    expect(live.bypassAcknowledged.value, isFalse);
    await hub.acknowledgeBypass(chat);
    expect(live.bypassAcknowledged.value, isTrue);
  });

  test('a session in bypass mode holds the prompt until the user allows it', () async {
    final hub = newHub();
    final chat = await newChat(acpSessionId: 'bypass-1');
    final live = await hub.session(chat);

    await expectLater(hub.prompt(chat, 'echo hi'), throwsA(isA<BypassNotAllowedException>()));

    expect(live.status.value, SessionStatus.idle);
    expect(live.bypassBlocked, isTrue);
    expect(live.canRetryPrompt.value, isTrue);
    expect(live.store.events.where((e) => e.kind == SessionEventKind.prompt), isEmpty);
    await hub.acknowledgeBypass(chat);
    await hub.retryPrompt(chat);
    expect(_agentText(live).join(), 'hi');
  });

  test('choosing bypass as the mode allows it for the chat', () async {
    final hub = newHub();
    final chat = await newChat();
    final live = await hub.session(chat);
    await hub.prompt(chat, 'echo hi');

    await hub.setConfigOption(chat, 'mode', 'bypassPermissions');

    expect(live.bypassAcknowledged.value, isTrue);
    expect(live.bypassBlocked, isFalse);
    await hub.prompt(chat, 'echo again');
    expect(_agentText(live).join(), 'hiagain');
  });

  test('permission requests wait for the user and are journaled', () async {
    final hub = newHub();
    final chat = await newChat();
    final live = await hub.session(chat);

    final turn = hub.prompt(chat, 'permission');
    await _until(live.status, (s) => s == SessionStatus.awaitingPermission);
    final request = live.store.events.singleWhere(
      (e) => e.kind == SessionEventKind.permissionRequest,
    );
    expect(hub.resolvePermission(chat, request.payload['requestId']! as String, 'allow'), isTrue);
    await turn;

    expect(live.status.value, SessionStatus.idle);
    expect(
      live.store.events.singleWhere((e) => e.kind == SessionEventKind.permissionResolution).payload,
      containsPair('optionId', 'allow'),
    );
    expect(_agentText(live), <String>['allow']);
    // The raw request frame is not journaled twice.
    expect(live.store.events.where((e) => e.kind == 'session/request_permission'), isEmpty);
  });

  test('stop ends a long turn without waiting for the setup lane', () async {
    final hub = newHub();
    final chat = await newChat();
    final live = await hub.session(chat);

    final turn = hub.prompt(chat, 'hang');
    await _untilSent(live);
    await hub.cancel(chat);
    expect(live.status.value, SessionStatus.cancelling);
    await turn;

    expect(live.status.value, SessionStatus.idle);
    expect(live.store.events.last.payload, containsPair('stopReason', 'cancelled'));
  });

  test('stop while waiting for permission declines the request', () async {
    final hub = newHub();
    final chat = await newChat();
    final live = await hub.session(chat);

    final turn = hub.prompt(chat, 'permission');
    await _until(live.status, (s) => s == SessionStatus.awaitingPermission);
    await hub.cancel(chat);
    await turn;

    expect(
      live.store.events.singleWhere((e) => e.kind == SessionEventKind.permissionResolution).payload,
      containsPair('outcome', 'cancelled'),
    );
    expect(_agentText(live), <String>['cancelled']);
  });

  test('a restarted app loads the agent session without journaling the replay', () async {
    final chat = await newChat();
    final first = newHub();
    await first.prompt(chat, 'echo one');
    final journal = (await first.session(chat)).store.events.length;
    await first.dispose();

    final second = newHub();
    final live = await second.session(chat);
    expect(live.store.events, hasLength(journal));
    final statuses = <SessionStatus>[];
    live.status.addListener(() => statuses.add(live.status.value));

    await second.prompt(chat, 'echo two');

    expect(statuses.take(3), <SessionStatus>[
      SessionStatus.starting,
      SessionStatus.loading,
      SessionStatus.idle,
    ]);
    expect(_agentText(live), isNot(contains('earlier answer')));
    expect(_agentText(live).join(), 'onetwo');
  });

  test('loading an unknown agent session fails with notFound and can start over', () async {
    final hub = newHub();
    final chat = await newChat(acpSessionId: 'missing');
    final live = await hub.session(chat);

    await expectLater(hub.prompt(chat, 'echo x'), throwsA(isA<Object>()));
    expect(live.status.value, SessionStatus.setupFailed);
    expect(live.problem.value?.kind, SessionProblemKind.notFound);
    expect(live.interrupted, SessionOperation.load);

    await hub.startNewAgentSession(chat);

    expect(live.status.value, SessionStatus.idle);
    expect(live.acpSessionId, isNot('missing'));
    expect(live.store.events.last.payload, containsPair('type', 'context_lost'));
    await hub.prompt(chat, 'echo again');
    expect(_agentText(live).join(), 'again');
  });

  test('authRequired on a prompt moves the chat to needsAuth', () async {
    final hub = newHub();
    final chat = await newChat();
    final live = await hub.session(chat);

    await hub.prompt(chat, 'auth');

    expect(live.status.value, SessionStatus.needsAuth);
    expect(live.problem.value?.kind, SessionProblemKind.auth);
    expect(live.interrupted, SessionOperation.prompt);
  });

  test('a login restarts the agent and offers to repeat the prompt', () async {
    final hub = newHub();
    final chat = await newChat();
    final live = await hub.session(chat);
    await hub.prompt(chat, 'auth');
    expect(live.status.value, SessionStatus.needsAuth);

    final login = await hub.login('fake', 'claude-ai-login');
    expect(await hub.login('fake', 'claude-ai-login'), same(login), reason: 'one login per agent');
    expect(await login.succeeded, isTrue);
    expect(login.output.value, contains('Logged in (--claudeai)'));
    await _until(live.status, (s) => s == SessionStatus.cold);

    expect(live.canRetryPrompt.value, isTrue);
    await hub.prompt(chat, 'echo after login');
    expect(_agentText(live).join(), 'after login');
  });

  test('an agent crash moves the busy chat to error and the next prompt restarts it', () async {
    final hub = newHub();
    final chat = await newChat();
    final live = await hub.session(chat);

    await hub.prompt(chat, 'crash');
    await _until(live.status, (s) => s == SessionStatus.error);
    expect(
      live.problem.value?.kind,
      isIn(<SessionProblemKind>[SessionProblemKind.crash, SessionProblemKind.transient]),
    );

    await hub.prompt(chat, 'echo back');
    expect(live.status.value, SessionStatus.idle);
    expect(_agentText(live).join(), 'back');
  });

  test('a prompt during a running turn is rejected', () async {
    final hub = newHub();
    final chat = await newChat();
    final live = await hub.session(chat);

    final turn = hub.prompt(chat, 'hang');
    await _until(live.status, (s) => s == SessionStatus.running);
    await expectLater(hub.prompt(chat, 'echo no'), throwsStateError);
    await hub.cancel(chat);
    await turn;
  });

  test('dispose cancels running turns and stops the agent', () async {
    final hub = newHub();
    final chat = await newChat();
    final live = await hub.session(chat);

    final turn = hub.prompt(chat, 'hang');
    await _until(live.status, (s) => s == SessionStatus.running);
    await hub.dispose();
    await turn.timeout(const Duration(seconds: 5));

    expect(live.status.value, SessionStatus.disposed);
    expect(live.store.isClosed, isTrue);
  });

  test('two chats share one agent process', () async {
    final hub = newHub();
    final a = await newChat();
    final b = await newChat();

    await Future.wait(<Future<void>>[hub.prompt(a, 'echo aa'), hub.prompt(b, 'echo bb')]);

    final liveA = await hub.session(a);
    final liveB = await hub.session(b);
    expect(_agentText(liveA).join(), 'aa');
    expect(_agentText(liveB).join(), 'bb');
    expect(liveA.acpSessionId, isNot(liveB.acpSessionId));
  });

  group('review regressions', () {
    test('two prompts at once in one chat send only one', () async {
      final hub = newHub();
      final chat = await newChat();
      final live = await hub.session(chat);

      final results = await Future.wait(<Future<Object?>>[
        hub.prompt(chat, 'echo first').then<Object?>((_) => null, onError: (Object e) => e),
        hub.prompt(chat, 'echo second').then<Object?>((_) => null, onError: (Object e) => e),
      ]);

      expect(results.whereType<StateError>(), hasLength(1));
      expect(live.store.events.where((e) => e.kind == SessionEventKind.prompt), hasLength(1));
      expect(live.status.value, SessionStatus.idle);
    });

    test('stop during turn preparation sends nothing and returns to idle', () async {
      final gate = Completer<void>();
      final hub = newHub(observers: <TurnObserver>[_GateObserver(gate.future)]);
      final chat = await newChat();
      final live = await hub.session(chat);

      final turn = hub.prompt(chat, 'echo never');
      await _until(live.status, (s) => s == SessionStatus.running);
      await hub.cancel(chat);
      gate.complete();
      await turn;

      expect(live.status.value, SessionStatus.idle);
      expect(live.store.events.where((e) => e.kind == SessionEventKind.prompt), isEmpty);
    });

    test('a crashed agent leaves no processes behind', () async {
      final hub = newHub();
      final chat = await newChat();
      final live = await hub.session(chat);
      await hub.prompt(chat, 'spawn');
      final pid = int.parse(File('${temp.path}/spawned.pid').readAsStringSync().trim());

      await hub.prompt(chat, 'crash');
      await _until(live.status, (s) => s == SessionStatus.error);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (Process.runSync('kill', <String>['-0', '$pid']).exitCode == 0) {
        if (DateTime.now().isAfter(deadline)) fail('the spawned process survived the crash');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(
        live.store.events.where((e) => e.payload['type'] == 'error'),
        hasLength(1),
        reason: 'one error event per failure',
      );
    });

    test('a permission request cannot be answered from another chat', () async {
      final hub = newHub();
      final chat = await newChat();
      final other = await newChat();
      final live = await hub.session(chat);

      final turn = hub.prompt(chat, 'permission');
      await _until(live.status, (s) => s == SessionStatus.awaitingPermission);
      final requestId =
          live.store.events
                  .singleWhere((e) => e.kind == SessionEventKind.permissionRequest)
                  .payload['requestId']!
              as String;

      expect(hub.resolvePermission(other, requestId, 'allow'), isFalse);
      expect(hub.resolvePermission(chat, requestId, 'reject'), isTrue);
      await turn;
      expect(_agentText(live), <String>['reject']);
    });

    test('a finished stop clears the force-stop offer and its timer', () async {
      final hub = newHub();
      final chat = await newChat();
      final live = await hub.session(chat);

      final turn = hub.prompt(chat, 'hang');
      await _until(live.status, (s) => s == SessionStatus.running);
      await hub.cancel(chat);
      await turn;
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      expect(live.canForceStop.value, isFalse);
      expect(live.problem.value, isNull);
    });
  });
}

final class _GateObserver implements TurnObserver {
  _GateObserver(this._gate);

  final Future<void> _gate;

  @override
  Future<Object?> beforeTurn(LiveSession session) async {
    await _gate;
    return null;
  }

  @override
  Future<Map<String, Object?>?> afterTurn(LiveSession session, Object? beforeToken) async => null;
}
