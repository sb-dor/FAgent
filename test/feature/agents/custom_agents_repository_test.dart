import 'package:async/async.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/agents/data/custom_agents_repository.dart';
import 'package:flutter_code_agent/src/feature/agents/models/custom_agent_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late CustomAgentsRepositoryImpl repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = CustomAgentsRepositoryImpl(database: database);
  });

  tearDown(() => database.close());

  const draft = CustomAgentDraft(
    name: 'My agent',
    executable: 'my-agent',
    arguments: ['--acp', '--fast'],
    environment: {'TOKEN': 'x'},
    rulesChannel: RulesChannel.systemPrompt,
  );

  group('CustomAgentsRepositoryImpl', () {
    test("add then watch emits custom:1 with the draft's fields", () async {
      final queue = StreamQueue(repository.watch());
      addTearDown(queue.cancel);
      expect(await queue.next, isEmpty);

      final id = await repository.add(draft);

      expect(id, 'custom:1');
      expect(await queue.next, [
        const AgentDefinition(
          id: 'custom:1',
          displayName: 'My agent',
          executable: 'my-agent',
          arguments: ['--acp', '--fast'],
          environment: {'TOKEN': 'x'},
          rulesChannel: RulesChannel.systemPrompt,
          source: AgentSource.custom,
        ),
      ]);
    });

    test('a draft without options defaults to the first-message channel', () async {
      await repository.add(const CustomAgentDraft(name: 'Plain', executable: 'plain'));

      final agent = (await repository.watch().first).single;
      expect(agent.arguments, isEmpty);
      expect(agent.environment, isEmpty);
      expect(agent.rulesChannel, RulesChannel.firstMessage);
    });

    test('update changes the definition', () async {
      final id = await repository.add(draft);
      final queue = StreamQueue(repository.watch());
      addTearDown(queue.cancel);
      await queue.next;

      await repository.update(
        id,
        const CustomAgentDraft(name: 'Renamed', executable: 'other', arguments: ['serve']),
      );

      final agent = (await queue.next).single;
      expect(agent.id, id);
      expect(agent.displayName, 'Renamed');
      expect(agent.executable, 'other');
      expect(agent.arguments, ['serve']);
      expect(agent.environment, isEmpty);
      expect(agent.rulesChannel, RulesChannel.firstMessage);
    });

    test('remove drops it', () async {
      final first = await repository.add(draft);
      final second = await repository.add(draft);
      expect(first, 'custom:1');
      expect(second, 'custom:2');

      await repository.remove(first);

      expect((await repository.watch().first).map((agent) => agent.id), [second]);
    });

    test('bad JSON in a row is skipped with a warning', () async {
      await repository.add(draft);
      await database
          .into(database.customAgentsTable)
          .insert(
            CustomAgentsTableCompanion.insert(
              name: 'Broken',
              executable: 'broken',
              arguments: const Value('{not json'),
            ),
          );

      final agents = await repository.watch().first;

      expect(agents.map((agent) => agent.id), ['custom:1']);
    });
  });
}
