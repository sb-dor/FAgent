import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_login_methods_controller.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_recovery_controller.dart';
import 'package:flutter_code_agent/src/feature/chat/data/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_agents_repository.dart';

final class _NoChatRepository implements IChatRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  group('ChatLoginMethodsController', () {
    test('follows the login methods of the agents repository', () async {
      final agents = MemoryAgentsRepository();
      final controller = ChatLoginMethodsController(repository: agents)..watch();
      addTearDown(controller.dispose);
      await pumpEventQueue();

      expect(controller.methodsOf('codex'), memoryCodexAgent.methods);
      expect(controller.methodsOf('claude'), memoryClaudeAgent.methods);
      expect(controller.methodsOf('unknown'), isEmpty);
      expect(controller.state['unknown'], isNull);

      agents.update(memoryCodexAgent.copyWith(methods: const <AgentLoginMethod>[]));
      await pumpEventQueue();
      expect(controller.methodsOf('codex'), isEmpty);
    });
  });

  group('ChatRecoveryController', () {
    ChatRecoveryController build(MemoryAgentsRepository agents) {
      final controller = ChatRecoveryController(chat: _NoChatRepository(), agents: agents);
      addTearDown(controller.dispose);
      return controller;
    }

    test('cancelLogin goes to the agents repository', () async {
      final agents = MemoryAgentsRepository();

      build(agents).cancelLogin('codex');
      await pumpEventQueue();

      expect(agents.calls, <String>['cancelLogin:codex']);
    });

    test('a browser login waits for the sign-in and reports it', () async {
      final agents = MemoryAgentsRepository(holdSignIns: true);
      final controller = build(agents)..login('codex', 'chat-gpt', cancellable: true);
      await pumpEventQueue();
      expect(controller.state, isA<ChatRecovery$InProgressState>());

      agents.finishSignIn('codex');
      await pumpEventQueue();

      expect(controller.state, isA<ChatRecovery$CompletedState>());
      expect(agents.calls, contains('login:codex:chat-gpt'));
    });

    test('a cancelled browser login did not succeed', () async {
      final agents = MemoryAgentsRepository(holdSignIns: true);
      final controller = build(agents)..login('codex', 'chat-gpt', cancellable: true);
      await pumpEventQueue();

      controller.cancelLogin('codex');
      await pumpEventQueue();

      expect(controller.state, isA<ChatRecovery$ErrorState>());
      // Mapped to a failed sign-in, not reported as an error.
      expect((controller.state as ChatRecovery$ErrorState).error, isNull);
    });

    test('a terminal login reports its output', () async {
      final agents = MemoryAgentsRepository();
      final controller = build(agents);
      final states = <ChatRecoveryState>[];
      controller.addListener(() => states.add(controller.state));

      controller.login('claude', 'claude-ai-login');
      await pumpEventQueue();

      expect(controller.state, isA<ChatRecovery$CompletedState>());
      expect(states.whereType<ChatRecovery$InProgressState>().last.output, contains('Signed in'));
    });
  });
}
