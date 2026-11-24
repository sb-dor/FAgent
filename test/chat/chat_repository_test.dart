import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_code_agent/_core/acp/agent_connection.dart';
import 'package:flutter_code_agent/_core/acp/agent_definition.dart';
import 'package:flutter_code_agent/_core/acp/agent_hub.dart';
import 'package:flutter_code_agent/_core/acp/session_event.dart';
import 'package:flutter_code_agent/_core/acp/session_problem.dart';
import 'package:flutter_code_agent/_core/acp/session_status.dart';
import 'package:flutter_code_agent/_core/database/database.dart';
import 'package:flutter_code_agent/_core/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/chat/data/chat_repository.dart';
import 'package:flutter_code_agent/chat/models/chat_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_agent_binary.dart';

void main() {
  late Directory temp;
  late AgentDefinition fakeAgent;
  late ShellEnvironment environment;
  late AppDatabase database;
  late AgentHub hub;
  late ChatRepositoryImpl repository;
  late int chat;

  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('chat_repository_test');
    fakeAgent = await compileFakeAgent(temp);
    environment = await ShellEnvironment.resolve();
  });

  tearDownAll(() => temp.deleteSync(recursive: true));

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    hub = AgentHub(
      database: database,
      environment: environment,
      agents: <String, AgentDefinition>{'fake': fakeAgent},
      connector: (definition, onPermission) => AgentConnection.start(
        definition: definition,
        environment: environment,
        onPermissionRequest: onPermission,
        initializeTimeout: const Duration(seconds: 20),
      ),
    );
    repository = ChatRepositoryImpl(hub: hub);
    final projectId = await database
        .into(database.projectsTable)
        .insert(ProjectsTableCompanion.insert(path: temp.path, name: 'project'));
    chat = await database
        .into(database.sessionsTable)
        .insert(SessionsTableCompanion.insert(projectId: projectId, agentId: 'fake'));
  });

  tearDown(() async {
    await hub.dispose();
    await database.close();
  });

  /// Listens to [repository]'s runtimes of [chat] until the test ends.
  List<ChatRuntime> collect(Stream<ChatRuntime> stream) {
    final runtimes = <ChatRuntime>[];
    final subscription = stream.listen(runtimes.add);
    addTearDown(subscription.cancel);
    return runtimes;
  }

  test('emits the chat once it is open, then on every journal append', () async {
    final runtimes = collect(repository.watch(chat));
    await pumpEventQueue();

    expect(runtimes, hasLength(1));
    expect(runtimes.single.sessionId, chat);
    expect(runtimes.single.agentId, 'fake');
    expect(runtimes.single.events, isEmpty);
    expect(runtimes.single.status, SessionStatus.cold);

    await hub.prompt(chat, 'echo hello');
    await pumpEventQueue();

    final last = runtimes.last;
    expect(last.status, SessionStatus.idle);
    expect(last.events.map((event) => event.kind), contains('agent_message_chunk'));
    expect(last.events.first.kind, SessionEventKind.prompt);
    expect(runtimes.length, greaterThan(2));
  });

  test('emits on a change of the live state, with the parsed options and commands', () async {
    final runtimes = collect(repository.watch(chat));
    await pumpEventQueue();
    final live = await hub.session(chat);

    live.status.value = SessionStatus.error;
    expect(runtimes.last.status, SessionStatus.error);

    live.problem.value = const SessionProblem(SessionProblemKind.crash, 'gone');
    expect(runtimes.last.problem?.kind, SessionProblemKind.crash);

    live.availableCommands.value = <Map<String, Object?>>[
      <String, Object?>{'name': 'compact', 'description': 'Compact'},
      <String, Object?>{'name': 5},
    ];
    expect(runtimes.last.commands.map((command) => command.name), <String>['compact']);

    live.configOptions.value = <Map<String, Object?>>[
      <String, Object?>{
        'id': 'mode',
        'name': 'Mode',
        'type': 'select',
        'currentValue': 'bypassPermissions',
        'options': <Map<String, Object?>>[
          <String, Object?>{'value': 'bypassPermissions', 'name': 'Bypass'},
        ],
      },
    ];
    expect(runtimes.last.configOptions.map((option) => option.id), <String>['mode']);
    expect(runtimes.last.bypassBlocked, isTrue);

    live.canForceStop.value = true;
    expect(runtimes.last.canForceStop, isTrue);
    // The commands are mapped again only when the agent sends new ones.
    expect(identical(runtimes.last.commands, runtimes[runtimes.length - 2].commands), isTrue);
  });

  test('the runtimes share one view of the journal instead of copying it', () async {
    final runtimes = collect(repository.watch(chat));
    await pumpEventQueue();
    final live = await hub.session(chat);

    live.status.value = SessionStatus.error;
    expect(runtimes, hasLength(2));
    expect(identical(runtimes.first.events, runtimes.last.events), isTrue);

    live.store.addAgentFrame('agent_message_chunk', const <String, Object?>{});
    expect(identical(runtimes.last.events, runtimes.first.events), isTrue);
    expect(runtimes.first.events, hasLength(1));
  });

  test('watchStatus emits the status and its changes, and nothing after cancel', () async {
    final statuses = <SessionStatus>[];
    final subscription = repository.watchStatus(chat).listen(statuses.add);
    await pumpEventQueue();
    final live = await hub.session(chat);
    expect(statuses, <SessionStatus>[SessionStatus.cold]);

    live
      ..canForceStop.value = true
      ..status.value = SessionStatus.starting;
    live.store.addAgentFrame('agent_message_chunk', const <String, Object?>{});
    expect(statuses, <SessionStatus>[SessionStatus.cold, SessionStatus.starting]);

    await subscription.cancel();
    live.status.value = SessionStatus.idle;
    await pumpEventQueue();
    expect(statuses, <SessionStatus>[SessionStatus.cold, SessionStatus.starting]);
  });

  test('watchStatus of a chat that cannot be opened is an error, then the stream ends', () async {
    final events = <String>[];
    final done = Completer<void>();
    repository
        .watchStatus(chat + 100)
        .listen(
          (_) => events.add('value'),
          onError: (Object error) => events.add('error'),
          onDone: done.complete,
        );

    await done.future;
    expect(events, <String>['error']);
  });

  test('emits nothing after the listener cancels', () async {
    final runtimes = <ChatRuntime>[];
    final subscription = repository.watch(chat).listen(runtimes.add);
    await pumpEventQueue();
    final live = await hub.session(chat);
    expect(runtimes, hasLength(1));

    await subscription.cancel();
    final count = runtimes.length;
    live
      ..status.value = SessionStatus.error
      ..canRetryPrompt.value = true
      ..preparingTurn.value = true;
    live.store.addAgentFrame('agent_message_chunk', const <String, Object?>{});
    await pumpEventQueue();

    expect(runtimes, hasLength(count));
  });

  test('a chat that cannot be opened is a stream error, then the stream ends', () async {
    final error = Completer<Object>();
    final done = Completer<void>();
    repository.watch(chat + 100).listen((_) {}, onError: error.complete, onDone: done.complete);

    expect(await error.future, isA<StateError>());
    await done.future;
  });
}
