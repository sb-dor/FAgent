import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentDefinition', () {
    test('builtins are claude, codex, gemini with the pinned commands', () {
      expect(AgentDefinition.builtins.map((agent) => agent.id), ['claude', 'codex', 'gemini']);
      expect(AgentDefinition.builtins.map((agent) => agent.displayName), [
        'Claude Code',
        'Codex',
        'Gemini CLI',
      ]);
      expect(
        AgentDefinition.builtins.every((agent) => agent.source == AgentSource.builtin),
        isTrue,
      );

      const claude = AgentDefinition.claude;
      expect(claude.executable, 'npx');
      expect(claude.arguments, ['-y', '@agentclientprotocol/claude-agent-acp@0.96.0']);
      expect(claude.minimumNodeMajor, 22);
      expect(claude.rulesChannel, RulesChannel.claudeMeta);
      expect(claude.keyVariables, isEmpty);

      const codex = AgentDefinition.codex;
      expect(codex.executable, 'npx');
      expect(codex.arguments, ['-y', '@agentclientprotocol/codex-acp@2.5.0']);
      expect(codex.minimumNodeMajor, 20);
      expect(codex.rulesChannel, RulesChannel.systemPrompt);
      expect(codex.loginArguments, isEmpty);
      expect(codex.keyVariables, {
        'api-key': ['CODEX_API_KEY', 'OPENAI_API_KEY'],
      });

      const gemini = AgentDefinition.gemini;
      expect(gemini.executable, 'npx');
      expect(gemini.arguments, ['-y', '@google/gemini-cli@0.66.0', '--acp']);
      expect(gemini.minimumNodeMajor, 22);
      expect(gemini.rulesChannel, RulesChannel.firstMessage);
      expect(gemini.keyVariables, {
        'gemini-api-key': ['GEMINI_API_KEY'],
      });
    });

    test('definitions with the same fields are equal', () {
      AgentDefinition build({String name = 'Mine', String variable = 'KEY'}) => AgentDefinition(
        id: 'custom:1',
        displayName: name,
        executable: '/bin/agent',
        arguments: const ['--acp'],
        environment: const {'A': 'b'},
        keyVariables: {
          'key': [variable],
        },
        rulesChannel: RulesChannel.systemPrompt,
        source: AgentSource.custom,
      );

      expect(build(), build());
      expect(build().hashCode, build().hashCode);
      expect(build(), isNot(build(name: 'Other')));
      expect(build(), isNot(build(variable: 'OTHER')));
    });

    test('a custom agent defaults to the first-message rules channel', () {
      const agent = AgentDefinition(id: 'custom:1', displayName: 'x', executable: 'x');
      expect(agent.rulesChannel, RulesChannel.firstMessage);
      expect(agent.source, AgentSource.builtin);
      expect(agent.keyVariables, isEmpty);
    });
  });
}
