import 'package:dart_acp_sdk/dart_acp_sdk.dart' show CancellationException;
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/agents/models/custom_agent_draft.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_agents_repository.dart';

void main() {
  test('logout and login change the status of Claude and emit again', () async {
    final repository = MemoryAgentsRepository();
    final seen = <List<AgentInfo>>[];
    final subscription = repository.watchAgents().listen(seen.add);
    await pumpEventQueue();
    expect(seen.single.map((a) => a.id), ['claude', 'codex', 'gemini']);
    expect(seen.single.first.status, AgentStatus.ready);

    await repository.logout('claude');
    await pumpEventQueue();
    expect(seen.last.first.status, AgentStatus.needsLogin);

    final login = await repository.login('claude', 'claude-ai-login');
    await pumpEventQueue();
    expect(await login!.succeeded, isTrue);
    expect(login.output.value, isNotEmpty);
    expect(seen.last.first.status, AgentStatus.ready);
    expect(repository.calls, ['logout:claude', 'login:claude:claude-ai-login']);

    await subscription.cancel();
    expect(repository.activeWatchers, 0);
  });

  test('a held browser sign-in waits for its end or a cancel', () async {
    final repository = MemoryAgentsRepository(holdSignIns: true);

    final cancelled = expectLater(
      repository.login('codex', 'chat-gpt'),
      throwsA(isA<CancellationException>()),
    );
    await pumpEventQueue();
    await repository.cancelLogin('codex');
    await cancelled;

    final finished = repository.login('codex', 'chat-gpt');
    await pumpEventQueue();
    repository.finishSignIn('codex');
    expect(await finished, isNull);
    expect(repository.agents[1].status, AgentStatus.ready);
  });

  test('custom agents are added, changed and removed', () async {
    final repository = MemoryAgentsRepository();
    const draft = CustomAgentDraft(name: 'Mine', executable: '/opt/mine');

    await repository.addCustom(draft);
    expect(repository.agents.last.custom, draft);
    await repository.updateCustom('custom:1', draft.copyWith(name: 'Renamed'));
    expect(repository.agents.last.name, 'Renamed');
    await repository.removeCustom('custom:1');

    expect(repository.agents.map((a) => a.id), ['claude', 'codex', 'gemini']);
    expect(repository.calls, [
      'addCustom:Mine',
      'updateCustom:custom:1:Renamed',
      'removeCustom:custom:1',
    ]);
  });
}
