import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/chat/data/chat_repository.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_view.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_problem_banner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_agents_repository.dart';
import '../../support/test_app.dart';

const ChatView _codexChat = ChatView(
  sessionId: 1,
  agentId: 'codex',
  items: <ChatItem>[],
  status: SessionStatus.needsAuth,
  problem: SessionProblem(SessionProblemKind.auth, 'Authentication required'),
);

Widget _banner(
  List<AgentLoginMethod> methods, {
  ValueChanged<String>? onLogin,
  VoidCallback? onCancelLogin,
  bool busy = false,
}) => ChatProblemBanner(
  view: _codexChat,
  busy: busy,
  onCancelLogin: onCancelLogin,
  loginFailed: false,
  loginMethods: methods,
  onRetry: () {},
  onStartNewAgentSession: () {},
  onForceStop: () {},
  onLogin: onLogin ?? (_) {},
  onRepeatPrompt: () {},
);

void main() {
  testWidgets("the banner's methods for a Codex chat", (tester) async {
    final methods = <String>[];
    await tester.pumpWidget(testApp(_banner(memoryCodexAgent.methods, onLogin: methods.add)));

    expect(find.text('The agent needs you to sign in.'), findsOneWidget);
    // A browser method is a button with the agent's own name for it.
    await tester.tap(find.widgetWithText(FilledButton, 'Login with ChatGPT'));
    expect(methods, <String>['chat-gpt']);
    // A key method without its variable explains the variable instead of offering a button.
    expect(find.widgetWithText(FilledButton, 'Use OPENAI_API_KEY'), findsNothing);
    expect(
      find.text(
        'To sign in with a key, set CODEX_API_KEY or OPENAI_API_KEY in your shell profile, '
        'then restart the app to pick up the key.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a key method with its variable is a button', (tester) async {
    final methods = <String>[];
    await tester.pumpWidget(
      testApp(
        _banner(<AgentLoginMethod>[
          memoryCodexAgent.methods.last.copyWith(keyPresent: true),
        ], onLogin: methods.add),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Use OPENAI_API_KEY'));

    expect(methods, <String>['api-key']);
    expect(find.textContaining('restart the app'), findsNothing);
  });

  testWidgets('unsupported methods are left out', (tester) async {
    await tester.pumpWidget(testApp(_banner(memoryGeminiAgent.methods)));

    expect(find.widgetWithText(FilledButton, 'Log in with Google'), findsOneWidget);
    expect(find.textContaining('Vertex AI'), findsNothing);
  });

  testWidgets('Claude methods keep their localized names', (tester) async {
    await tester.pumpWidget(
      testApp(_banner(memoryClaudeAgent.methods), locale: const Locale('ru')),
    );

    expect(find.text('Агент просит войти в аккаунт.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Войти через Claude.ai'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Войти через Anthropic Console'), findsOneWidget);
  });

  testWidgets('the buttons are off while a sign-in runs', (tester) async {
    await tester.pumpWidget(testApp(_banner(memoryCodexAgent.methods, busy: true)));

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Login with ChatGPT'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('needsAuth with no methods shows the message and the Settings pointer', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(_banner(const <AgentLoginMethod>[])));

    expect(find.text('The agent needs you to sign in.'), findsOneWidget);
    expect(find.text('Sign in from Settings → Agents.'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('only methods set up in the agent also point to Settings', (tester) async {
    await tester.pumpWidget(
      testApp(
        _banner(const <AgentLoginMethod>[
          AgentLoginMethod(id: 'vertex-ai', name: 'Vertex AI', kind: AgentLoginKind.unsupported),
        ]),
      ),
    );

    expect(find.text('Sign in from Settings → Agents.'), findsOneWidget);
  });

  testWidgets('a running browser sign-in can be cancelled from the banner', (tester) async {
    var cancels = 0;
    await tester.pumpWidget(
      testApp(_banner(memoryCodexAgent.methods, busy: true, onCancelLogin: () => cancels++)),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));

    expect(cancels, 1);
  });

  testWidgets('no Cancel without a running cancellable sign-in', (tester) async {
    await tester.pumpWidget(testApp(_banner(memoryCodexAgent.methods, onCancelLogin: () {})));
    expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsNothing);

    await tester.pumpWidget(testApp(_banner(memoryClaudeAgent.methods, busy: true)));
    expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsNothing);
  });

  group('ChatRepositoryImpl', () {
    late AppDatabase database;
    late AgentHub hub;

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
      hub = AgentHub(
        database: database,
        environment: const ShellEnvironment(<String, String>{'PATH': '/usr/bin:/bin'}),
      );
    });

    tearDown(() async {
      await hub.dispose();
      await database.close();
    });

    test('follows the login methods of the agents repository', () async {
      final agents = MemoryAgentsRepository();
      final repository = ChatRepositoryImpl(hub: hub, agents: agents);
      final seen = <Map<String, List<AgentLoginMethod>>>[];
      final subscription = repository.watchLoginMethods().listen(seen.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      expect(seen.last['codex'], memoryCodexAgent.methods);
      expect(seen.last['claude'], memoryClaudeAgent.methods);
      expect(seen.last['unknown'], isNull);

      agents.update(memoryCodexAgent.copyWith(methods: const <AgentLoginMethod>[]));
      await pumpEventQueue();
      expect(seen.last['codex'], isEmpty);
    });

    test('cancelLogin goes to the agents repository', () async {
      final agents = MemoryAgentsRepository();

      await ChatRepositoryImpl(hub: hub, agents: agents).cancelLogin('codex');

      expect(agents.calls, <String>['cancelLogin:codex']);
    });

    test('a browser login waits for the sign-in and reports it', () async {
      final agents = MemoryAgentsRepository(holdSignIns: true);
      final repository = ChatRepositoryImpl(hub: hub, agents: agents);

      final succeeded = repository.login('codex', 'chat-gpt', onOutput: (_) {});
      await pumpEventQueue();
      agents.finishSignIn('codex');

      expect(await succeeded, isTrue);
      expect(agents.calls, contains('login:codex:chat-gpt'));
    });

    test('a cancelled browser login did not succeed', () async {
      final agents = MemoryAgentsRepository(holdSignIns: true);
      final repository = ChatRepositoryImpl(hub: hub, agents: agents);

      final succeeded = repository.login('codex', 'chat-gpt', onOutput: (_) {});
      await pumpEventQueue();
      await agents.cancelLogin('codex');

      expect(await succeeded, isFalse);
    });

    test('a terminal login reports its output', () async {
      final agents = MemoryAgentsRepository();
      final repository = ChatRepositoryImpl(hub: hub, agents: agents);
      final lines = <List<String>>[];

      final succeeded = await repository.login('claude', 'claude-ai-login', onOutput: lines.add);

      expect(succeeded, isTrue);
      expect(lines.last, contains('Signed in'));
    });
  });
}
