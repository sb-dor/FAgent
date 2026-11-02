import 'package:async/async.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/skills/data/chat_skills_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/models/skill_library.dart';
import 'package:flutter_code_agent/src/feature/skills/models/skills_for_chat.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_skills_repository.dart';

void main() {
  late AppDatabase database;
  late ChatSkillsRepositoryImpl repository;
  late int sessionId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = ChatSkillsRepositoryImpl(database: database);
    final projectId = await database
        .into(database.projectsTable)
        .insert(ProjectsTableCompanion.insert(path: '/work/app', name: 'app'));
    sessionId = await database
        .into(database.sessionsTable)
        .insert(
          SessionsTableCompanion.insert(
            projectId: projectId,
            agentId: 'claude',
            title: const Value<String>('chat'),
          ),
        );
  });

  tearDown(() => database.close());

  Future<List<ChatSkillStateRow>> rows() => database.select(database.chatSkillStatesTable).get();

  group('ChatSkillsRepositoryImpl', () {
    test(
      'a skill turned off for the chat is a row; back to the project value removes it',
      () async {
        expect(await repository.current(sessionId), isEmpty);

        await repository.set(sessionId, 'skill:user:a', enabled: false, projectEnabled: true);
        expect(await repository.current(sessionId), {'skill:user:a': false});
        expect(await rows(), hasLength(1));

        await repository.set(sessionId, 'skill:user:a', enabled: true, projectEnabled: true);
        expect(await repository.current(sessionId), isEmpty);
        expect(await rows(), isEmpty);
      },
    );

    test('a skill turned on against its project is a row too', () async {
      await repository.set(sessionId, 'skill:user:a', enabled: true, projectEnabled: false);

      expect(await repository.current(sessionId), {'skill:user:a': true});
    });

    test('setting the same value twice keeps one row', () async {
      await repository.set(sessionId, 'skill:user:a', enabled: false, projectEnabled: true);
      await repository.set(sessionId, 'skill:user:a', enabled: false, projectEnabled: true);

      expect(await rows(), hasLength(1));
    });

    test('chats do not share rows', () async {
      final other = await database
          .into(database.sessionsTable)
          .insert(SessionsTableCompanion.insert(projectId: 1, agentId: 'claude'));
      await repository.set(sessionId, 'skill:user:a', enabled: false, projectEnabled: true);

      expect(await repository.current(other), isEmpty);
    });

    test('deleting the chat drops its rows', () async {
      await repository.set(sessionId, 'skill:user:a', enabled: false, projectEnabled: true);

      await (database.delete(database.sessionsTable)..where((t) => t.id.equals(sessionId))).go();

      expect(await rows(), isEmpty);
    });

    test('watch emits the current states, then every change, and closes on cancel', () async {
      final queue = StreamQueue<Map<String, bool>>(repository.watch(sessionId));

      expect(await queue.next, isEmpty);
      await repository.set(sessionId, 'skill:user:a', enabled: false, projectEnabled: true);
      expect(await queue.next, {'skill:user:a': false});
      await repository.set(sessionId, 'skill:user:a', enabled: true, projectEnabled: true);
      expect(await queue.next, isEmpty);

      await queue.cancel();
    });

    test('watch does not repeat equal states and ignores other chats', () async {
      final other = await database
          .into(database.sessionsTable)
          .insert(SessionsTableCompanion.insert(projectId: 1, agentId: 'claude'));
      final emitted = <Map<String, bool>>[];
      final subscription = repository.watch(sessionId).listen(emitted.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await repository.set(other, 'skill:user:a', enabled: false, projectEnabled: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emitted, [<String, bool>{}]);
      await subscription.cancel();
    });
  });

  group('skillsForChat', () {
    final library = SkillLibrary(
      skills: [
        memorySkill('a', source: SkillSource.project),
        memorySkill('b', source: SkillSource.user),
        memorySkill('c').copyWith(enabled: false),
      ],
    );

    List<String> names(Map<String, bool> states) => [
      for (final skill in skillsForChat(library, states)) skill.name,
    ];

    test('without overrides it is the skills enabled for the project', () {
      expect(names(const {}), ['a', 'b']);
    });

    test('a skill turned off for the chat is left out', () {
      expect(names({'skill:project:a': false}), ['b']);
    });

    test('an override does not bring in a skill the project has off', () {
      expect(names({'skill:builtin:c': true}), ['a', 'b']);
    });

    test('rules are not skills', () {
      final withRule = SkillLibrary(skills: library.skills, rules: [memoryRule('r')]);

      expect(skillsForChat(withRule, const {}).every((s) => s.kind == KnowledgeKind.skill), isTrue);
    });
  });
}
