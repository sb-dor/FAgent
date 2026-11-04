import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/acp/agent_connection.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_queue_controller.dart';
import 'package:flutter_code_agent/src/feature/chat/models/queued_prompt.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/data/prompt_sending_repository.dart';
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

List<String> _agentText(LiveSession live) => <String>[
  for (final event in live.store.events)
    if (event.kind == 'agent_message_chunk')
      if (event.payload case {'params': {'update': {'content': {'text': final String text}}}}) text,
];

/// The queue of a chat with a real hub and the fake agent, around the bypass gate.
void main() {
  late Directory temp;
  late AgentDefinition fakeAgent;
  late ShellEnvironment environment;
  late AppDatabase database;
  late AgentHub hub;

  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('chat_queue_bypass_test');
    fakeAgent = await compileFakeAgent(temp);
    environment = await ShellEnvironment.resolve();
  });

  tearDownAll(() => temp.deleteSync(recursive: true));

  setUp(() {
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
      cancelTimeout: const Duration(seconds: 1),
    );
  });

  tearDown(() async {
    await hub.dispose();
    await database.close();
  });

  test('a message queued while the first prompt is held for bypass stays queued; Allow repeats '
      'the first', () async {
    final projectId = await database
        .into(database.projectsTable)
        .insert(ProjectsTableCompanion.insert(path: temp.path, name: 'project'));
    // The fake agent loads `bypass-*` sessions in bypassPermissions mode.
    final chat = await database
        .into(database.sessionsTable)
        .insert(
          SessionsTableCompanion.insert(
            projectId: projectId,
            agentId: 'fake',
            acpSessionId: const Value<String?>('bypass-queue'),
          ),
        );
    final live = await hub.session(chat);
    final queue = ChatQueueController(
      sessionId: chat,
      repository: PromptSendingRepositoryImpl(hub: hub),
    )..follow(live.status);
    addTearDown(queue.dispose);

    // M1 goes; M2 is queued (⌘↵) while M1's agent session is being set up.
    final first = hub.prompt(chat, 'echo first');
    await _until(live.status, (status) => status.isBusy);
    queue.add(const QueuedPrompt(text: 'echo second', resources: <Map<String, Object?>>[]));
    await expectLater(first, throwsA(isA<BypassNotAllowedException>()));
    // The setup reached `idle` without a turn: the queue tries M2 on the next event.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(live.bypassBlocked, isTrue);
    expect(queue.state.items.map((prompt) => prompt.text), <String>['echo second']);
    expect(queue.state.paused, isTrue);
    expect(live.canRetryPrompt.value, isTrue);

    // Allow: the held prompt is M1.
    await hub.acknowledgeBypass(chat);
    await hub.retryPrompt(chat);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(_agentText(live).join(), 'first');
    expect(live.status.value, SessionStatus.idle);
    expect(queue.state.items.map((prompt) => prompt.text), <String>['echo second']);
    expect(queue.state.paused, isTrue, reason: 'the queue waits for the user after the refusal');
  });
}
