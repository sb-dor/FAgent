import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agents_exceptions.dart';
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
    expect(await login.succeeded, isTrue);
    expect(login.output.value, isNotEmpty);
    expect(seen.last.first.status, AgentStatus.ready);
    expect(repository.calls, ['logout:claude', 'login:claude:claude-ai-login']);

    await subscription.cancel();
    expect(repository.activeWatchers, 0);
  });

  test('preview agents refuse actions', () async {
    final repository = MemoryAgentsRepository();

    await expectLater(repository.login('codex', 'x'), throwsA(isA<AgentPreviewException>()));
    await expectLater(repository.install('codex'), throwsA(isA<AgentPreviewException>()));
    expect(repository.calls, ['login:codex:x', 'install:codex']);
  });
}
