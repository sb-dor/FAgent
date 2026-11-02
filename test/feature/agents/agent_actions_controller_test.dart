import 'dart:async';

import 'package:flutter_code_agent/src/feature/agents/controller/agent_actions_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_agents_repository.dart';

/// Sign-out waits for [release], so it holds the actions' handler.
final class _SlowLogoutAgents extends MemoryAgentsRepository {
  _SlowLogoutAgents() : super(holdSignIns: true);

  final Completer<void> release = Completer<void>();

  @override
  Future<void> logout(String agentId) async {
    await release.future;
    return super.logout(agentId);
  }
}

void main() {
  test('cancel while another action is in flight still cancels', () async {
    final agents = _SlowLogoutAgents();
    final controller = AgentActionsController(repository: agents);
    addTearDown(controller.dispose);

    controller.login('codex', memoryCodexAgent.methods.first);
    expect(controller.state.signingIn, <String>{'codex'});
    controller.logout('claude');
    await pumpEventQueue();
    expect(controller.isProcessing, isTrue);

    controller.cancelLogin('codex');
    await pumpEventQueue();

    expect(agents.calls, contains('cancelLogin:codex'));
    expect(controller.state.signingIn, isEmpty);
    expect(controller.state.error, isNull);
    agents.release.complete();
    await pumpEventQueue();
    expect(agents.calls, contains('logout:claude'));
  });

  test('a second sign-in of the same agent is dropped', () async {
    final agents = MemoryAgentsRepository(holdSignIns: true);
    final controller = AgentActionsController(repository: agents);
    addTearDown(controller.dispose);

    controller
      ..login('codex', memoryCodexAgent.methods.first)
      ..login('codex', memoryCodexAgent.methods.first);
    await pumpEventQueue();

    expect(agents.calls.where((call) => call.startsWith('login:codex')), hasLength(1));
    agents.finishSignIn('codex');
    await pumpEventQueue();
    expect(controller.state.signingIn, isEmpty);
  });
}
