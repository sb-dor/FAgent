import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agent_options_catalog.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agent_probe.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agents_repository.dart';
import 'package:flutter_code_agent/src/feature/agents/data/custom_agents_repository.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_probe_result.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_recovery_controller.dart';
import 'package:flutter_code_agent/src/feature/chat/data/chat_repository.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_config_widget.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/fake_agent_binary.dart';
import '../../support/memory_agents_repository.dart';
import '../../support/test_app.dart';

/// A probe that never runs anything.
final class _NoProbe implements IAgentProbe {
  @override
  Future<AgentProbeResult> probe(AgentDefinition agent, {Duration? authStatusWait}) async =>
      const AgentProbeResult();

  @override
  Future<void> dispose() async {}
}

/// Polls until [condition] holds, for up to ten seconds.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('the condition did not hold within 10 seconds');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('methods appearing later show their buttons without reopening the chat', (
    tester,
  ) async {
    useDesktopView(tester);
    // Codex is not checked yet: no methods.
    final agents = MemoryAgentsRepository(
      agents: <AgentInfo>[
        memoryClaudeAgent,
        memoryCodexAgent.copyWith(
          status: AgentStatus.checking,
          methods: const <AgentLoginMethod>[],
        ),
      ],
    );
    final dependencies = testDependencies(agentsRepository: agents);
    addTearDown(dependencies.database.close);
    final database = dependencies.database;
    final projectId = (await tester.runAsync(
      () => database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: '/tmp', name: 'p')),
    ))!;
    final sessionId = (await tester.runAsync(
      () => database
          .into(database.sessionsTable)
          .insert(SessionsTableCompanion.insert(projectId: projectId, agentId: 'codex')),
    ))!;
    await tester.pumpWidget(
      testApp(
        dependencies: dependencies,
        ChatConfigWidget(
          sessionId: sessionId,
          project: Project(id: projectId, path: '/tmp', name: 'p', isFlutter: false),
        ),
      ),
    );
    final live = (await tester.runAsync(() => dependencies.agentHub.session(sessionId)))!;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    live
      ..problem.value = const SessionProblem(SessionProblemKind.auth, 'Authentication required')
      ..status.value = SessionStatus.needsAuth;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('The agent needs you to sign in.'), findsOneWidget);
    expect(find.text('Sign in from Settings → Agents.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Login with ChatGPT'), findsNothing);

    agents.update(memoryCodexAgent);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.widgetWithText(FilledButton, 'Login with ChatGPT'), findsOneWidget);
    expect(find.text('Sign in from Settings → Agents.'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  group('with a real agent', () {
    late Directory temp;
    late AgentDefinition fake;

    setUpAll(() async {
      temp = Directory.systemTemp.createTempSync('chat_sign_in_test');
      fake = await compileFakeAgent(temp);
    });

    tearDownAll(() => temp.deleteSync(recursive: true));

    test('cancel from the chat ends the sign-in', () async {
      final requests = File(p.join(temp.path, 'requests.jsonl'));
      final database = AppDatabase(NativeDatabase.memory());
      final environment = await ShellEnvironment.resolve();
      final hub = AgentHub(
        database: database,
        environment: environment,
        agents: <String, AgentDefinition>{
          'codex': AgentDefinition(
            id: 'codex',
            displayName: 'Codex',
            executable: fake.executable,
            environment: <String, String>{
              'FAKE_AGENT_REQUESTS_FILE': requests.path,
              'FAKE_AGENT_AUTH_HANG': '1',
            },
          ),
        },
      );
      final agents = AgentsRepositoryImpl(
        hub: hub,
        environment: environment,
        catalog: AgentOptionsCatalogImpl(database: database),
        customAgents: CustomAgentsRepositoryImpl(database: database),
        probe: _NoProbe(),
      );
      final controller = ChatRecoveryController(
        repository: ChatRepositoryImpl(hub: hub, agents: agents),
      );
      addTearDown(() async {
        controller.dispose();
        await hub.dispose();
        await database.close();
      });
      int authenticates() => requests.existsSync()
          ? requests
                .readAsLinesSync()
                .where((line) => line.isNotEmpty)
                .where(
                  (line) => (jsonDecode(line) as Map<String, Object?>)['method'] == 'authenticate',
                )
                .length
          : 0;

      controller.login('codex', 'browser-login', cancellable: true);
      await _until(() => authenticates() == 1);
      expect(
        controller.state,
        isA<ChatRecovery$InProgressState>().having((s) => s.cancellable, 'cancellable', isTrue),
      );

      controller.cancelLogin('codex');
      await _until(() => controller.state is! ChatRecovery$InProgressState);

      expect(controller.state, isA<ChatRecovery$ErrorState>());
      // A new sign-in starts a new authenticate: the cancelled one is over.
      controller.login('codex', 'browser-login', cancellable: true);
      await _until(() => authenticates() == 2);
      controller.cancelLogin('codex');
      await _until(() => controller.state is! ChatRecovery$InProgressState);
    });
  });
}
